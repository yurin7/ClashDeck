import 'package:flutter/foundation.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/rule_layout.dart';
import '../core/edit/import_links.dart';
import '../core/model/profile.dart';
import '../core/parse/share_link.dart';
import '../core/validate/validator.dart';
import '../core/yaml/yaml_doc.dart';
import '../data/profile_store.dart';

/// 编辑一份配置时的全部状态：源码文本、语义视图、校验结果、撤销栈、脏标记。
///
/// 所有修改都必须经过 [apply]，它是**唯一**的写入入口 —— 这样撤销/脏标记/
/// 校验刷新不可能被某处漏掉。
class EditorState extends ChangeNotifier {
  EditorState({
    required YamlDoc doc,
    this.fileName,
    String? savedText,
    this.historyLimit = 50,
    this.migratedDefaultGroup = false,
  }) : _doc = doc,
       _savedText = savedText ?? doc.text;

  /// 解析文本；旧配置缺「默认」组时自动迁移，并把迁移前的文本当作"已保存"，
  /// 这样编辑器会显示成未保存，用户保存后才会真正落盘。
  factory EditorState.fromText(
    String text, {
    String? fileName,
    String? savedText,
    int historyLimit = 50,
  }) {
    final parsed = YamlDoc.parse(text);
    final migrated = ConfigOps.migrateDefaultGroup(parsed);
    final changed = !identical(migrated.text, parsed.text);
    return EditorState(
      doc: migrated,
      fileName: fileName,
      savedText: changed ? (savedText ?? text) : savedText,
      historyLimit: historyLimit,
      migratedDefaultGroup: changed,
    );
  }

  /// 撤销栈上限。
  final int historyLimit;

  /// 这次加载是否补建了「默认」组（旧配置迁移）。
  final bool migratedDefaultGroup;

  YamlDoc _doc;
  String? fileName;
  String _savedText;

  final List<YamlDoc> _undo = [];
  final List<YamlDoc> _redo = [];

  /// 最近一次操作失败的原因（UI 用 SnackBar 展示）。
  String? lastError;

  YamlDoc get doc => _doc;
  Profile get profile => Profile.from(_doc);
  ValidationReport get report => ConfigValidator.validate(_doc);

  bool get isValidYaml => _doc.isValid;
  bool get dirty => _doc.text != _savedText;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// 应用一次编辑。成功返回 true（并压入撤销栈），失败返回 false 且状态不变。
  bool apply(YamlDoc Function(YamlDoc doc) op) {
    lastError = null;
    YamlDoc next;
    try {
      next = op(_doc);
    } on ConfigEditException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = '$e';
      notifyListeners();
      return false;
    }
    if (identical(next.text, _doc.text)) return true; // 空操作
    _undo.add(_doc);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _doc = next;
    notifyListeners();
    return true;
  }

  /// 直接替换文本（导入、外部编辑）。
  void replaceText(String text, {bool asSaved = false}) {
    if (text == _doc.text) return;
    _undo.add(_doc);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _doc = YamlDoc.parse(text);
    if (asSaved) _savedText = text;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_doc);
    _doc = _undo.removeLast();
    lastError = null;
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_doc);
    _doc = _redo.removeLast();
    lastError = null;
    notifyListeners();
  }

  /// 落盘。成功后清除脏标记。
  Future<void> save(ProfileStore store) async {
    final name = fileName;
    if (name == null) throw StateError('还没有文件名，先 create()');
    await store.write(name, _doc.text);
    _savedText = _doc.text;
    notifyListeners();
  }

  /// 首次保存：给定名字，在仓库里建文件。
  Future<void> saveAs(ProfileStore store, String displayName) async {
    final stored = await store.create(displayName, _doc.text);
    fileName = stored.fileName;
    _savedText = _doc.text;
    notifyListeners();
  }

  // ------------------------------------------------------------ 常用快捷操作

  bool addProxy(
    Map<String, Object?> proxy, {
    List<String> intoGroups = const [],
  }) => apply((d) => ConfigOps.addProxy(d, proxy, intoGroups: intoGroups));

  bool deleteProxy(String name) => apply((d) => ConfigOps.deleteProxy(d, name));

  bool moveMember(String node, String from, String to) => apply(
    (d) => ConfigOps.moveMember(d, node: node, fromGroup: from, toGroup: to),
  );

  bool addGroupMember(String group, String member) =>
      apply((d) => ConfigOps.addGroupMember(d, group, member));

  bool removeGroupMember(String group, String member) =>
      apply((d) => ConfigOps.removeGroupMember(d, group, member));

  /// 组内成员换位（链式代理的「前移/后移」与拖放插入）。
  bool moveGroupMember(String group, int from, int to) =>
      apply((d) => ConfigOps.moveGroupMember(d, group, from, to));

  /// 新增一条规则。默认按分区插到所属区块的第一位（本地精确 / 在线 / 兜底）；
  /// 显式给 [at] 时按旧行为插到指定下标（测试与特殊场景用）。
  bool addRule(String rule, {int? at}) => at == null
      ? apply((d) => RuleLayout.insertRuleDoc(d, rule))
      : apply((d) => ConfigOps.addRule(d, rule, at: at));

  /// 把 rules 段按「本地精确 → 在线 → 兜底」重排一遍。
  ///
  /// 幂等：已经排好时文本不变，[apply] 会当成空操作，不置脏、不进 undo。
  bool normalizeRules() => apply((d) => RuleLayout.normalizeDoc(d));

  bool deleteRule(int index) => apply((d) => ConfigOps.deleteRule(d, index));

  bool moveRule(int from, int to) =>
      apply((d) => ConfigOps.moveRule(d, from, to));

  // ------------------------------------------------------- 批量导入（链接/订阅）

  /// 这段文本里能解析出几个节点（只解析不写入，用来先给用户看个数字）。
  int countShareLinks(String text) => parseShareLinks(text).length;

  /// 把一段文本里的分享链接导入本配置；[group] 非空时顺带加进该组。
  bool importLinkText(String text, {String? group}) =>
      apply((d) => importLinks(d, text, group: group).doc);

  /// 把已经解析好的节点列表导入（订阅拉回来的走这条）。
  bool importProxyList(
    List<Map<String, Object?>> proxies, {
    String? group,
    bool skipExisting = false,
  }) => apply(
    (d) =>
        importProxies(d, proxies, group: group, skipExisting: skipExisting).doc,
  );
}
