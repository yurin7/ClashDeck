import '../model/rule_zone.dart';
import '../yaml/yaml_doc.dart';

/// 规则段的**文本级**整理与插入。
///
/// 为什么不走 yaml_edit：`YamlEditor` 对 sequence 做增删时会重写整个序列，
/// 行内注释、空行一律丢失。这里只切 `rules:` 这一段，其余字节原样保留，
/// 能让「重排」这件事对用户可见地安全：段外一个字符都不动。
///
/// 不变式（由 [normalize] 保证）：
/// * 顺序为 本地精确区块 → 在线规则集区块 → 兜底块（MATCH / FINAL）；
/// * 区块内部保持原有相对顺序；
/// * 每条规则带上前方紧贴它的注释行，行内注释属于行本身；
/// * 顺序已经正确时返回原字符串（幂等，调用方可据此跳过写盘）。
class RuleLayout {
  const RuleLayout._();

  /// 把 `rules:` 段重排成「本地 → 在线 → 兜底」。
  ///
  /// 找不到 `rules:`、或该键不是块状列表（例如写成 `rules: [a, b]`）时，
  /// 原样返回——宁可不动，也不猜测用户意图。
  static String normalize(String text) {
    final block = _RulesBlock.parse(text);
    if (block == null) return text;
    final next = block.orderedText();
    if (next == block.text) return text;
    return text.replaceRange(block.start, block.end, next);
  }

  /// 按分区把一条规则插到它所属区块的第一位（[atZoneEnd] 时插到区块末尾）。
  ///
  /// 批量导入用末尾插入：既落在正确的区块里，又不会把导入块的顺序倒过来。
  /// 便于单测的纯文本版本；真正改文档时用 [insertRuleDoc]。
  static String insertRule(String text, String rule, {bool atZoneEnd = false}) {
    final line = rule.trim();
    if (line.isEmpty) return text;

    final block = _RulesBlock.parse(text);
    if (block == null) {
      final trimmed = text.trimRight();
      final sep = trimmed.isEmpty ? '' : '\n\n';
      return '$trimmed${sep}rules:\n  - $line\n';
    }

    final zone = ruleZoneOf(line);
    final at = atZoneEnd
        ? switch (zone) {
            RuleZone.local => block.localCount,
            RuleZone.online => block.onlineCount,
            RuleZone.terminal => block.entries.length,
          }
        : switch (zone) {
            RuleZone.local => 0,
            RuleZone.online => block.localCount,
            RuleZone.terminal => block.entries.length,
          };
    return block.insertAt(at, line).applyTo(text);
  }

  /// 文档版本：解析新文本，解析失败时退回原文档（编辑失败即无副作用）。
  static YamlDoc normalizeDoc(YamlDoc doc) {
    final next = normalize(doc.text);
    if (identical(next, doc.text) || next == doc.text) return doc;
    final parsed = YamlDoc.parse(next);
    return parsed.isValid ? parsed : doc;
  }

  /// 文档版本：把 [rule] 插到所属区块（[atZoneEnd] 时为区块末尾）。
  static YamlDoc insertRuleDoc(
    YamlDoc doc,
    String rule, {
    bool atZoneEnd = false,
  }) {
    final next = insertRule(doc.text, rule, atZoneEnd: atZoneEnd);
    if (next == doc.text) return doc;
    final parsed = YamlDoc.parse(next);
    return parsed.isValid ? parsed : doc;
  }

  /// 检测 MATCH / FINAL 是否已经不在末尾（用于 UI 提示）。
  static bool hasTerminalNotLast(String text) {
    final block = _RulesBlock.parse(text);
    if (block == null) return false;
    final terminals = <int>[];
    for (var i = 0; i < block.entries.length; i++) {
      if (ruleZoneOf(block.entries[i].firstLine) == RuleZone.terminal) {
        terminals.add(i);
      }
    }
    if (terminals.isEmpty) return false;
    return terminals.last != block.entries.length - 1;
  }
}

/// `rules:` 段的解析结果：段在原文中的位置 + 头部 + 条目 + 尾部。
class _RulesBlock {
  _RulesBlock({
    required this.start,
    required this.end,
    required this.text,
    required this.header,
    required this.entries,
    required this.tail,
    required this.indent,
  });

  /// 段在原文中的起止（`text.substring(start, end) == text`）。
  final int start;
  final int end;
  final String text;

  /// `rules:` 那一行，以及首个条目之前属于段头部的注释/空行。
  final List<String> header;
  final List<_RuleEntry> entries;

  /// 最后一条之后残留的注释/空行（跟着段尾走，不参与排序）。
  final List<String> tail;

  /// 条目缩进，例如 `'  '`。
  final String indent;

  int get localCount => entries.where((e) => e.zone == RuleZone.local).length;

  /// 在线区块的条目数，用于把新规则插到在线块末尾。
  int get onlineCount => entries.where((e) => e.zone == RuleZone.online).length;

  _RulesBlock insertAt(int index, String line) {
    final next = [...entries]..insert(index, _RuleEntry(['$indent- $line']));
    return _RulesBlock(
      start: start,
      end: end,
      text: text,
      header: header,
      entries: next,
      tail: tail,
      indent: indent,
    );
  }

  /// 生成重排后的段文本（不含段外内容）。
  String orderedText() {
    final body = _bodyText();
    return text.endsWith('\n') ? '$body\n' : body;
  }

  String _bodyText() {
    final locals = entries.where((e) => e.zone == RuleZone.local);
    final onlines = entries.where((e) => e.zone == RuleZone.online);
    final terminals = entries.where((e) => e.zone == RuleZone.terminal);
    final lines = <String>[
      ...header,
      for (final group in [locals, onlines, terminals])
        for (final entry in group) ...entry.lines,
      ...tail,
    ];
    return lines.join('\n');
  }

  /// 把本块的新文本写回整段 YAML。
  String applyTo(String yaml) => yaml.replaceRange(start, end, orderedText());

  static _RulesBlock? parse(String yaml) {
    final lines = yaml.split('\n');
    var offset = 0;
    final starts = List<int>.filled(lines.length, 0);
    for (var i = 0; i < lines.length; i++) {
      starts[i] = offset;
      offset += lines[i].length + 1; // 加上换行符
    }

    var keyIndex = -1;
    var flowEmpty = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('rules:')) {
        final rest = line.substring('rules:'.length).trim();
        if (rest.isEmpty || rest.startsWith('#')) {
          keyIndex = i;
          break;
        }
        if (rest == '[]') {
          keyIndex = i;
          flowEmpty = true;
          break;
        }
        return null; // flow 形式，不猜
      }
    }
    if (keyIndex < 0) return null;

    // 段结束：下一个顶级键（顶格、非注释、非列表项）。
    var endIndex = lines.length;
    for (var i = keyIndex + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final first = line[0];
      if (first == ' ' || first == '\t') continue;
      if (first == '#' || first == '-') continue;
      endIndex = i;
      break;
    }

    final header = <String>[];
    final entries = <_RuleEntry>[];
    final tail = <String>[];
    var pendingComments = <String>[];
    var indent = '  ';
    var sawEntry = false;

    // 文本以换行结尾时 split 会多出一个空串，别把它当成段内的空行。
    final limit =
        endIndex == lines.length && lines.isNotEmpty && lines.last.isEmpty
        ? lines.length - 1
        : endIndex;

    for (var i = keyIndex; i < limit; i++) {
      final raw = lines[i];
      if (i == keyIndex) {
        if (flowEmpty) {
          header.add('rules:');
        } else {
          header.add(raw);
        }
        continue;
      }
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        if (!sawEntry && trimmed.isEmpty) {
          // 首个条目前的空行算段头，保持原来的呼吸感。
          header.add(raw);
        } else {
          // 注释紧贴下一条规则，重排时跟着它一起走。
          pendingComments.add(raw);
        }
        continue;
      }
      if (trimmed.startsWith('- ')) {
        if (!sawEntry) {
          final dash = raw.indexOf('- ');
          indent = raw.substring(0, dash);
        }
        sawEntry = true;
        entries.add(_RuleEntry([...pendingComments, raw]));
        pendingComments = <String>[];
        continue;
      }
      // 段内缩进的非列表行：当成上一条的续行/尾注，保守地挂到 tail。
      tail.add(raw);
    }
    if (pendingComments.isNotEmpty) tail.addAll(pendingComments);

    final blockStart = starts[keyIndex];
    final blockEnd = endIndex < lines.length ? starts[endIndex] : yaml.length;
    return _RulesBlock(
      start: blockStart,
      end: blockEnd,
      text: yaml.substring(blockStart, blockEnd),
      header: header,
      entries: entries,
      tail: tail,
      indent: indent,
    );
  }
}

/// 一条规则条目：首行是规则本身，前面的注释行跟它一起搬。
class _RuleEntry {
  _RuleEntry(this.lines);

  final List<String> lines;

  String get firstLine => lines.lastWhere(
    (line) => !line.trim().startsWith('#'),
    orElse: () => lines.isEmpty ? '' : lines.last,
  );

  RuleZone get zone => ruleZoneOf(firstLine);
}
