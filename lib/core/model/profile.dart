import '../yaml/yaml_doc.dart';

/// 节点（proxies[i]）。
class ProxyEntry {
  const ProxyEntry({
    required this.index,
    required this.name,
    required this.type,
    required this.raw,
  });

  final int index;
  final String name;
  final String type;

  /// 该节点的完整键值（保序、纯 Dart），含未知字段。
  final Map<String, Object?> raw;

  String get server => '${raw['server'] ?? ''}';
  int? get port {
    final p = raw['port'];
    if (p is int) return p;
    if (p is String) return int.tryParse(p);
    return null;
  }

  String get subtitle {
    final s = server;
    final p = port;
    return p == null ? s : '$s:$p';
  }

  String? operator [](String key) {
    final v = raw[key];
    return v == null ? null : '$v';
  }
}

/// 策略组（proxy-groups[i]）。
class GroupEntry {
  const GroupEntry({
    required this.index,
    required this.name,
    required this.type,
    required this.members,
    required this.raw,
  });

  final int index;
  final String name;
  final String type;

  /// YAML 里**显式写出**的成员列表（`proxies:`）。
  final List<String> members;

  /// 该组的完整键值（保序、纯 Dart）。
  final Map<String, Object?> raw;

  bool get includeAll =>
      raw['include-all'] == true || raw['include-all-proxies'] == true;

  bool get includeAllProviders => raw['include-all-providers'] == true;

  bool get hasFilter =>
      raw['filter'] != null ||
      raw['exclude-filter'] != null ||
      raw['exclude-type'] != null;

  /// 成员是否由内核在运行时计算（filter / include-all 等）。
  /// 这类组不能靠拖拽增删成员，UI 必须给出提示。
  bool get computedMembers => includeAll || includeAllProviders || hasFilter;

  /// `use:` 引用的 provider 列表。
  List<String> get useProviders {
    final v = raw['use'];
    if (v is List) return v.map((e) => '$e').toList();
    return const [];
  }

  String get typeLabel => switch (type) {
    'select' => '手动选择',
    'url-test' => '自动测速',
    'fallback' => '故障转移',
    'load-balance' => '负载均衡',
    'relay' => '链式代理',
    _ => type,
  };
}

/// 单条规则，字符串形式 `TYPE,PAYLOAD,TARGET[,no-resolve]`。
class RuleEntry {
  const RuleEntry({
    required this.index,
    required this.raw,
    required this.type,
    required this.payload,
    required this.target,
    required this.options,
  });

  final int index;
  final String raw;
  final String type;
  final String payload;
  final String target;
  final List<String> options;

  bool get noResolve => options.contains('no-resolve');

  /// MATCH / FINAL 规则只有两段：`MATCH,target`，目标在第 1 段。
  bool get isTerminal => type == 'MATCH' || type == 'FINAL';

  /// 目标策略在这条规则的逗号分段里的下标。
  int get targetIndex => isTerminal ? 1 : 2;

  static RuleEntry parse(int index, String raw) {
    final parts = raw.split(',').map((e) => e.trim()).toList();
    if (parts.isEmpty || parts.every((e) => e.isEmpty)) {
      return RuleEntry(
        index: index,
        raw: raw,
        type: '',
        payload: '',
        target: '',
        options: const [],
      );
    }
    final type = parts[0];
    final terminal = type == 'MATCH' || type == 'FINAL';
    if (terminal) {
      return RuleEntry(
        index: index,
        raw: raw,
        type: type,
        payload: '',
        target: parts.length > 1 ? parts[1] : '',
        options: parts.length > 2 ? parts.sublist(2) : const [],
      );
    }
    if (parts.length < 3) {
      return RuleEntry(
        index: index,
        raw: raw,
        type: type,
        payload: parts.length > 1 ? parts[1] : '',
        target: '',
        options: const [],
      );
    }
    return RuleEntry(
      index: index,
      raw: raw,
      type: type,
      payload: parts[1],
      target: parts[2],
      options: parts.sublist(3),
    );
  }
}

/// 一份配置的只读语义视图。由 [YamlDoc] 派生，不持有可写状态。
class Profile {
  Profile._({
    required this.doc,
    required this.root,
    required this.proxies,
    required this.groups,
    required this.rules,
  });

  final YamlDoc doc;

  /// 顶层键值（保序、纯 Dart），不含任何裁剪。
  final Map<String, Object?> root;

  final List<ProxyEntry> proxies;
  final List<GroupEntry> groups;
  final List<RuleEntry> rules;

  factory Profile.from(YamlDoc doc) {
    final root = doc.plainRoot;
    final proxies = <ProxyEntry>[];
    final rawProxies = root['proxies'];
    if (rawProxies is List) {
      for (var i = 0; i < rawProxies.length; i++) {
        final item = rawProxies[i];
        if (item is! Map) continue;
        final map = item.map((k, v) => MapEntry('$k', v));
        proxies.add(
          ProxyEntry(
            index: i,
            name: '${map['name'] ?? '#$i'}',
            type: '${map['type'] ?? 'unknown'}',
            raw: map,
          ),
        );
      }
    }

    final groups = <GroupEntry>[];
    final rawGroups = root['proxy-groups'];
    if (rawGroups is List) {
      for (var i = 0; i < rawGroups.length; i++) {
        final item = rawGroups[i];
        if (item is! Map) continue;
        final map = item.map((k, v) => MapEntry('$k', v));
        final membersRaw = map['proxies'];
        groups.add(
          GroupEntry(
            index: i,
            name: '${map['name'] ?? '#$i'}',
            type: '${map['type'] ?? 'select'}',
            members: membersRaw is List
                ? membersRaw.map((e) => '$e').toList()
                : const <String>[],
            raw: map,
          ),
        );
      }
    }

    final rules = <RuleEntry>[];
    final rawRules = root['rules'];
    if (rawRules is List) {
      for (var i = 0; i < rawRules.length; i++) {
        final item = rawRules[i];
        if (item is Map || item is List) continue;
        rules.add(RuleEntry.parse(i, '$item'));
      }
    }

    return Profile._(
      doc: doc,
      root: root,
      proxies: proxies,
      groups: groups,
      rules: rules,
    );
  }

  String get mode => '${root['mode'] ?? 'rule'}';
  String get name => '${root['name'] ?? ''}';

  Set<String> get proxyNames => proxies.map((e) => e.name).toSet();
  Set<String> get groupNames => groups.map((e) => e.name).toSet();

  /// 内置策略名，规则里合法引用。
  static const builtinTargets = <String>{
    'DIRECT',
    'REJECT',
    'REJECT-DROP',
    'PASS',
    'COMPATIBLE',
    'GLOBAL',
  };

  /// 代理页固定展示的两张系统策略卡：不进 YAML 建同名组，只读展示。
  static const systemPolicyTargets = <String>['DIRECT', 'REJECT'];

  Map<String, ProxyEntry> get proxyByName => {
    for (final p in proxies) p.name: p,
  };

  Map<String, GroupEntry> get groupByName => {
    for (final g in groups) g.name: g,
  };

  /// 出现在某个组显式成员列表里的节点名。
  Set<String> get nodesInGroups => {for (final g in groups) ...g.members};

  /// 还没归入任何组的节点（"节点池"视图用来提示未归类节点）。
  List<ProxyEntry> get ungroupedNodes {
    final used = nodesInGroups;
    return proxies.where((p) => !used.contains(p.name)).toList();
  }

  /// 所有可以作为规则/成员目标的策略名（组 + 内置）。
  Set<String> get allTargets => {...groupNames, ...builtinTargets};

  ProxyEntry? proxy(String name) => proxyByName[name];
  GroupEntry? group(String name) => groupByName[name];
}
