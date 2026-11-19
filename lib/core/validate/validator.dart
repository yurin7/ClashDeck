import '../model/profile.dart';
import '../yaml/yaml_doc.dart';

enum IssueSeverity { error, warning, info }

/// 一条校验结果。`code` 稳定可用于测试/忽略列表，`message` 面向用户。
class Issue {
  const Issue({
    required this.severity,
    required this.code,
    required this.message,
    this.subject,
    this.path = const [],
  });

  final IssueSeverity severity;
  final String code;
  final String message;

  /// 涉及的对象名（节点名/组名），便于 UI 高亮定位。
  final String? subject;

  /// 在 YAML 中的路径，便于 UI 跳转（如 ['proxies', 3, 'uuid']）。
  final List<Object?> path;

  bool get isError => severity == IssueSeverity.error;

  @override
  String toString() {
    final tag = switch (severity) {
      IssueSeverity.error => '错误',
      IssueSeverity.warning => '警告',
      IssueSeverity.info => '提示',
    };
    return '[$tag] $message';
  }
}

class ValidationReport {
  const ValidationReport(this.issues);

  final List<Issue> issues;

  bool get hasErrors => issues.any((e) => e.isError);
  bool get isClean => issues.isEmpty;

  List<Issue> get errors =>
      issues.where((e) => e.severity == IssueSeverity.error).toList();
  List<Issue> get warnings =>
      issues.where((e) => e.severity == IssueSeverity.warning).toList();

  /// 能不能直接交给内核热重载。
  bool get canSubmit => !hasErrors;

  Map<String, List<Issue>> get bySubject {
    final out = <String, List<Issue>>{};
    for (final i in issues) {
      final key = i.subject ?? '';
      (out[key] ??= <Issue>[]).add(i);
    }
    return out;
  }
}

/// 配置静态校验：全部是纯函数，不依赖 flutter，可在单测里跑。
///
/// 级别约定：
/// * **error** —— 内核会拒绝加载或行为明显错乱（缺 server、悬空引用、规则缺目标…）；
/// * **warning** —— 内核能加载但很可能不是用户想要的（MATCH 不在最后、重名…）；
/// * **info** —— 只是提醒（运行时计算成员的组无法拖拽等）。
class ConfigValidator {
  ConfigValidator._();

  static const groupTypes = <String>{
    'select',
    'url-test',
    'fallback',
    'load-balance',
    'relay',
  };

  static const modes = <String>{'rule', 'global', 'direct', 'script'};

  /// 需要 `server` + `port` 的入站类型（wireguard 用 ip/peers，不在此列）。
  static const _needsHostPort = <String>{
    'vless',
    'vmess',
    'trojan',
    'ss',
    'ssr',
    'socks5',
    'http',
    'hysteria2',
    'hy2',
    'tuic',
    'snell',
    'ssh',
    'anytls',
  };

  static ValidationReport validate(YamlDoc doc) {
    final issues = <Issue>[];
    if (!doc.isValid) {
      final err = doc.error;
      return ValidationReport([
        Issue(
          severity: IssueSeverity.error,
          code: 'yaml-parse',
          message: 'YAML 语法错误：${err?.message ?? '根节点不是映射'}',
        ),
      ]);
    }

    final profile = Profile.from(doc);
    _checkPorts(profile, issues);
    _checkProxyNames(profile, issues);
    _checkProxyFields(profile, issues);
    _checkGroups(profile, issues);
    _checkRules(profile, issues);
    _checkReferences(profile, issues);
    _checkMode(profile, issues);
    _checkTerminalRule(profile, issues);

    issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return ValidationReport(issues);
  }

  // ---------------------------------------------------------------- 检查项

  static void _checkPorts(Profile p, List<Issue> issues) {
    for (final key in const [
      'port',
      'socks-port',
      'mixed-port',
      'redir-port',
      'tproxy-port',
    ]) {
      final v = p.root[key];
      if (v == null) continue;
      final n = v is int ? v : int.tryParse('$v');
      if (n == null || n < 1 || n > 65535) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'bad-port',
            message: '$key 必须是 1-65535 的端口，当前是 $v',
            path: [key],
          ),
        );
      }
    }
  }

  static void _checkProxyNames(Profile p, List<Issue> issues) {
    final seen = <String, int>{};
    for (var i = 0; i < p.proxies.length; i++) {
      final name = p.proxies[i].name;
      if (name.trim().isEmpty) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'empty-proxy-name',
            message: '第 ${i + 1} 个节点没有名字',
            path: ['proxies', i, 'name'],
          ),
        );
        continue;
      }
      if (seen.containsKey(name)) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'duplicate-proxy-name',
            message: '节点名重复：$name（第 ${seen[name]! + 1} 个和第 ${i + 1} 个）',
            subject: name,
            path: ['proxies', i, 'name'],
          ),
        );
      } else {
        seen[name] = i;
      }
    }
    for (var i = 0; i < p.groups.length; i++) {
      final name = p.groups[i].name;
      if (seen.containsKey(name)) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'name-shadow',
            message: '策略组与节点同名：$name，引用时含义不明确',
            subject: name,
            path: ['proxy-groups', i, 'name'],
          ),
        );
      }
    }
  }

  static void _checkProxyFields(Profile p, List<Issue> issues) {
    for (var i = 0; i < p.proxies.length; i++) {
      final node = p.proxies[i];
      final raw = node.raw;
      final type = node.type;
      if (!raw.containsKey('type') || type == 'unknown') {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'proxy-missing-type',
            message: '节点 ${node.name} 缺少 type',
            subject: node.name,
            path: ['proxies', i, 'type'],
          ),
        );
        continue;
      }
      if (_needsHostPort.contains(type)) {
        if (node.server.trim().isEmpty) {
          issues.add(
            Issue(
              severity: IssueSeverity.error,
              code: 'proxy-missing-server',
              message: '节点 ${node.name} 缺少 server',
              subject: node.name,
              path: ['proxies', i, 'server'],
            ),
          );
        }
        if (node.port == null) {
          issues.add(
            Issue(
              severity: IssueSeverity.error,
              code: 'proxy-missing-port',
              message: '节点 ${node.name} 缺少合法的 port',
              subject: node.name,
              path: ['proxies', i, 'port'],
            ),
          );
        }
      }
      if ((type == 'vless' || type == 'vmess') && raw['uuid'] == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'proxy-missing-uuid',
            message: '节点 ${node.name}（$type）缺少 uuid',
            subject: node.name,
            path: ['proxies', i, 'uuid'],
          ),
        );
      }
      if (type == 'trojan' && raw['password'] == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'proxy-missing-password',
            message: '节点 ${node.name}（trojan）缺少 password',
            subject: node.name,
            path: ['proxies', i, 'password'],
          ),
        );
      }
      if ((type == 'hysteria2' || type == 'hy2' || type == 'tuic') &&
          raw['password'] == null &&
          raw['token'] == null &&
          raw['uuid'] == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'proxy-missing-secret',
            message: '节点 ${node.name}（$type）缺少 password/token/uuid',
            subject: node.name,
            path: ['proxies', i],
          ),
        );
      }
      if (type == 'wireguard' && raw['private-key'] == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'wireguard-missing-key',
            message: '节点 ${node.name}（wireguard）缺少 private-key',
            subject: node.name,
            path: ['proxies', i, 'private-key'],
          ),
        );
      }
      final dialer = raw['dialer-proxy'];
      if (dialer is String &&
          dialer.isNotEmpty &&
          p.proxy(dialer) == null &&
          p.group(dialer) == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'dangling-dialer-proxy',
            message: '节点 ${node.name} 的 dialer-proxy 指向不存在的 $dialer',
            subject: node.name,
            path: ['proxies', i, 'dialer-proxy'],
          ),
        );
      }
    }
  }

  static void _checkGroups(Profile p, List<Issue> issues) {
    final names = <String, int>{};
    final providerNames = _providerNames(p);
    for (var i = 0; i < p.groups.length; i++) {
      final g = p.groups[i];
      final path = ['proxy-groups', i];
      if (g.name.trim().isEmpty) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'empty-group-name',
            message: '第 ${i + 1} 个策略组没有名字',
            path: [...path, 'name'],
          ),
        );
        continue;
      }
      if (names.containsKey(g.name)) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'duplicate-group-name',
            message: '策略组名重复：${g.name}',
            subject: g.name,
            path: [...path, 'name'],
          ),
        );
      } else {
        names[g.name] = i;
      }
      final type = g.raw['type'];
      if (type == null) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'group-missing-type',
            message: '策略组 ${g.name} 缺少 type',
            subject: g.name,
            path: [...path, 'type'],
          ),
        );
      } else if (!groupTypes.contains('$type')) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'unknown-group-type',
            message: '策略组 ${g.name} 的 type「$type」不是常见的 ${groupTypes.join('/')}',
            subject: g.name,
            path: [...path, 'type'],
          ),
        );
      }
      for (final m in g.members) {
        if (p.proxy(m) != null ||
            p.group(m) != null ||
            Profile.builtinTargets.contains(m)) {
          continue;
        }
        if (providerNames.contains(m)) continue;
        issues.add(
          Issue(
            // 字面成员不存在时 mihomo 会直接退出（proxy group ... not found），
            // 必须按错误拦下，不能只给警告。computed 组（include-all/filter）
            // 的成员由内核动态生成，缺项不致命。
            severity: g.computedMembers
                ? IssueSeverity.info
                : IssueSeverity.error,
            code: 'dangling-member',
            message: '策略组 ${g.name} 里的成员「$m」不存在',
            subject: g.name,
            path: [...path, 'proxies'],
          ),
        );
      }
      for (final u in g.useProviders) {
        if (!providerNames.contains(u)) {
          issues.add(
            Issue(
              severity: IssueSeverity.warning,
              code: 'unknown-provider',
              message: '策略组 ${g.name} 的 use 引用了未定义的 proxy-provider「$u」',
              subject: g.name,
              path: [...path, 'use'],
            ),
          );
        }
      }
      if (g.type == 'select' && g.members.isEmpty && !g.computedMembers) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'empty-select-group',
            message: '手动选择组 ${g.name} 没有任何成员',
            subject: g.name,
            path: path,
          ),
        );
      }
      if (g.type == 'relay' && g.members.length < 2) {
        issues.add(
          Issue(
            severity: IssueSeverity.info,
            code: 'thin-relay',
            message: '链式代理组 ${g.name} 成员少于 2 个',
            subject: g.name,
            path: path,
          ),
        );
      }
    }
  }

  static void _checkRules(Profile p, List<Issue> issues) {
    final ruleProviderNames = _ruleProviderNames(p);
    for (var i = 0; i < p.rules.length; i++) {
      final r = p.rules[i];
      final path = ['rules', i];
      if (r.type.isEmpty) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'empty-rule',
            message: '第 ${i + 1} 条规则是空的',
            path: path,
          ),
        );
        continue;
      }
      if (r.target.isEmpty) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'rule-missing-target',
            message: '规则「${r.raw}」缺少目标策略',
            path: path,
          ),
        );
        continue;
      }
      final known =
          p.proxy(r.target) != null ||
          p.group(r.target) != null ||
          Profile.builtinTargets.contains(r.target);
      if (!known) {
        issues.add(
          Issue(
            // mihomo 加载规则时找不到目标策略会直接退出（proxy [...] not found）。
            severity: IssueSeverity.error,
            code: 'unknown-rule-target',
            message: '规则「${r.raw}」的目标「${r.target}」不存在',
            subject: r.target,
            path: path,
          ),
        );
      }
      // RULE-SET 的规则集名必须在 rule-providers 里定义；未定义时 mihomo
      // 报 `rule set [x] not found` 并退出。
      if (r.type == 'RULE-SET' && !ruleProviderNames.contains(r.payload)) {
        issues.add(
          Issue(
            severity: IssueSeverity.error,
            code: 'rule-set-provider-missing',
            message: '规则「${r.raw}」引用的规则集「${r.payload}」未定义',
            subject: r.payload,
            path: path,
          ),
        );
      }
    }
  }

  static void _checkTerminalRule(Profile p, List<Issue> issues) {
    final terminals = <int>[];
    for (var i = 0; i < p.rules.length; i++) {
      if (p.rules[i].isTerminal) terminals.add(i);
    }
    if (terminals.isEmpty) {
      issues.add(
        const Issue(
          severity: IssueSeverity.warning,
          code: 'no-terminal-rule',
          message: '没有 MATCH/FINAL 兜底规则，未匹配的流量会走默认策略',
        ),
      );
      return;
    }
    if (terminals.length > 1) {
      issues.add(
        Issue(
          severity: IssueSeverity.warning,
          code: 'multiple-terminal-rules',
          message: '有 ${terminals.length} 条 MATCH/FINAL，只有第一条会生效',
          path: ['rules', terminals[1]],
        ),
      );
    }
    final last = terminals.last;
    if (last != p.rules.length - 1) {
      issues.add(
        Issue(
          severity: IssueSeverity.warning,
          code: 'terminal-rule-not-last',
          message: 'MATCH/FINAL 必须放在最后，当前后面还有 ${p.rules.length - 1 - last} 条',
          path: ['rules', last],
        ),
      );
    }
  }

  static void _checkReferences(Profile p, List<Issue> issues) {
    for (final g in p.groups) {
      final sub = g.raw['sub-rules'];
      if (sub != null && sub is! Map) {
        issues.add(
          Issue(
            severity: IssueSeverity.warning,
            code: 'bad-sub-rules',
            message: '策略组 ${g.name} 的 sub-rules 应当是映射',
            subject: g.name,
          ),
        );
      }
    }
  }

  static void _checkMode(Profile p, List<Issue> issues) {
    final mode = p.root['mode'];
    if (mode == null) return;
    if (!modes.contains('$mode')) {
      issues.add(
        Issue(
          severity: IssueSeverity.warning,
          code: 'unknown-mode',
          message: 'mode「$mode」不是常见值（${modes.join('/')}）',
          path: ['mode'],
        ),
      );
    }
  }

  static Set<String> _providerNames(Profile p) {
    final out = <String>{};
    for (final key in const ['proxy-providers', 'rule-providers']) {
      final v = p.root[key];
      if (v is Map) out.addAll(v.keys.map((e) => '$e'));
    }
    return out;
  }

  /// 只取 rule-providers 的键：RULE-SET 的规则集只能来自这里。
  static Set<String> _ruleProviderNames(Profile p) {
    final v = p.root['rule-providers'];
    return v is Map ? v.keys.map((e) => '$e').toSet() : <String>{};
  }
}
