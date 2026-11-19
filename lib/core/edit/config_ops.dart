import '../model/profile.dart';
import '../yaml/yaml_doc.dart';
import 'member_order.dart';

/// 默认 select 组的名字：规则默认指向它，新节点也自动加入。
const String kDefaultGroupName = 'DEFAULT';

/// 上一批自动建的旧名，只用于迁移识别。
const String kLegacyDefaultGroupName = '默认';

/// 「自动选择」组：url-test 按延迟挑最快的节点，排在 DEFAULT 之后。
const String kAutoGroupName = '自动选择';

/// 「自动选择」的测速地址与间隔（秒）。
const String kAutoGroupTestUrl = 'http://www.gstatic.com/generate_204';
const int kAutoGroupInterval = 300;

/// url-test 的容差：延迟差在这个范围内就沿用当前节点，避免来回切。
const int kAutoGroupTolerance = 50;

/// 所有编辑操作：`旧文档 -> 新文档` 的纯函数，失败抛 [ConfigEditException]。
///
/// 设计原则：
/// * **只碰需要改的那一小段文本**（yaml_edit 的 span 级替换），其余字节不动；
/// * 用**名字**定位而不是下标，避免 UI 并发操作导致错位；
/// * 任何操作后如果 YAML 不再合法，直接抛异常，不产出半成品。
class ConfigOps {
  ConfigOps._();

  // ---------------------------------------------------------------- 节点

  /// 追加一个节点；同时可选地把它加进若干显式成员组。
  static YamlDoc addProxy(
    YamlDoc doc,
    Map<String, Object?> proxy, {
    List<String> intoGroups = const [],
  }) {
    final name = _requireName(proxy);
    var next = _appendProxy(doc, proxy);
    for (final g in intoGroups) {
      next = addGroupMember(next, g, name, missingGroupOk: true);
    }
    // 新节点一律进默认组：它带着全部节点 + DIRECT + REJECT，是规则的默认出口。
    next = addGroupMember(next, kDefaultGroupName, name, missingGroupOk: true);
    next = ensureDefaultGroup(next);
    // 节点排在 DIRECT / REJECT 之前：规则默认命中的是节点，不是系统策略。
    next = _placeBeforeBuiltins(next, kDefaultGroupName, name);
    // 「自动选择」跟着节点走：还没有这个组时先建，成员始终等于全部节点。
    next = ensureAutoGroup(next);
    return _insertIntoAutoGroup(next, name);
  }

  /// 默认组的名字。规则默认指向它，新节点也会自动加入。
  static const String defaultGroupName = kDefaultGroupName;

  /// 保证配置里有默认 select 组，且成员覆盖全部节点 + DIRECT + REJECT。
  ///
  /// 规则默认 target 指向它，所以缺了会让新规则无处可去；这里按需创建/补齐，
  /// 已有的成员顺序尽量保持（新节点追加在末尾）。
  static YamlDoc ensureDefaultGroup(YamlDoc doc) {
    final profile = Profile.from(doc);
    final names = [
      for (final proxy in profile.proxies) proxy.name,
      'DIRECT',
      'REJECT',
    ];
    final existing = profile.group(kDefaultGroupName);
    if (existing == null) {
      return addGroup(doc, {
        'name': kDefaultGroupName,
        'type': 'select',
      }, members: names);
    }
    var next = doc;
    for (final member in names) {
      if (existing.members.contains(member)) continue;
      // 插入后由 addGroupMember 统一归一化：节点按 proxies 顺序排在内置之前。
      next = addGroupMember(
        next,
        kDefaultGroupName,
        member,
        missingGroupOk: true,
      );
    }
    return next;
  }

  /// 保证配置里有「自动选择」组（url-test），排在 DEFAULT 之后。
  ///
  /// 成员始终等于**全部节点**（不含 DIRECT / REJECT）。没有节点、也没有规则
  /// 指向它时先不写：代理页用虚拟卡占位，等有节点再落盘。组已存在时每次调用
  /// 都把成员同步成当前节点列表，所以加删节点不用另外维护。
  static YamlDoc ensureAutoGroup(YamlDoc doc) {
    final profile = Profile.from(doc);
    final names = [for (final proxy in profile.proxies) proxy.name];
    final existing = profile.group(kAutoGroupName);
    if (existing != null) {
      if (_sameMembers(existing.members, names)) return doc;
      return setGroupMembers(doc, kAutoGroupName, names);
    }
    final referenced = profile.rules.any(
      (rule) => rule.target == kAutoGroupName,
    );
    if (names.isEmpty && !referenced) return doc;
    final group = <String, Object?>{
      'name': kAutoGroupName,
      'type': 'url-test',
      'url': kAutoGroupTestUrl,
      'interval': kAutoGroupInterval,
      'tolerance': kAutoGroupTolerance,
      'proxies': <Object?>[...names],
    };
    final current = doc.plainAt(['proxy-groups']);
    if (current is! List || current.isEmpty) {
      return doc.apply((e) => e.update(['proxy-groups'], <Object?>[group]));
    }
    final at =
        (profile.group(kDefaultGroupName)?.index ?? current.length - 1) + 1;
    if (at >= current.length) {
      return doc.apply((e) => e.appendToList(['proxy-groups'], group));
    }
    return doc.apply((e) => e.insertIntoList(['proxy-groups'], at, group));
  }

  static bool _sameMembers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<String> _proxyOrder(Profile profile) => [
    for (final proxy in profile.proxies) proxy.name,
  ];

  /// 把节点追加进「自动选择」组；没有这个组、或已经在里面时原样返回。
  static YamlDoc _insertIntoAutoGroup(YamlDoc doc, String name) {
    final auto = Profile.from(doc).group(kAutoGroupName);
    if (auto == null || auto.members.contains(name)) return doc;
    return addGroupMember(doc, kAutoGroupName, name);
  }

  /// 把成员挪到第一个内置出站（DIRECT / REJECT …）之前；已经在前面就原样返回。
  static YamlDoc _placeBeforeBuiltins(
    YamlDoc doc,
    String groupName,
    String member,
  ) {
    final group = Profile.from(doc).group(groupName);
    if (group == null) return doc;
    final index = group.members.indexOf(member);
    if (index < 0) return doc;
    final builtinAt = _firstBuiltinIndex(doc, groupName);
    if (builtinAt == null || index < builtinAt) return doc;
    final next = removeGroupMember(doc, groupName, member);
    return addGroupMember(next, groupName, member, at: builtinAt);
  }

  /// 组里第一个内置出站（DIRECT / REJECT …）的下标；没有就返回 null。
  static int? _firstBuiltinIndex(YamlDoc doc, String groupName) {
    final group = Profile.from(doc).group(groupName);
    if (group == null) return null;
    final at = group.members.indexWhere(Profile.builtinTargets.contains);
    return at < 0 ? null : at;
  }

  /// 加载旧配置时的迁移：把上一批自动建的「默认」组并入 `DEFAULT`，或者补建。
  ///
  /// 与 [ensureDefaultGroup] 的区别：这里**不补齐**已有组的成员（用户可能
  /// 故意把 DIRECT 移出去），只解决"规则默认 target 没有落脚点"的问题。
  static YamlDoc migrateDefaultGroup(YamlDoc doc) {
    var profile = Profile.from(doc);
    if (profile.group(kDefaultGroupName) != null) return doc;
    // 上一批把默认组叫「默认」；改名时同步改写所有 target 引用。
    if (profile.group(kLegacyDefaultGroupName) != null) {
      return renameGroup(doc, kLegacyDefaultGroupName, kDefaultGroupName);
    }
    final group = <String, Object?>{
      'name': kDefaultGroupName,
      'type': 'select',
      'proxies': <Object?>[
        for (final proxy in profile.proxies) proxy.name,
        'DIRECT',
        'REJECT',
      ],
    };
    final current = doc.plainAt(['proxy-groups']);
    final groups = <Object?>[group, if (current is List) ...current];
    return doc.apply((e) => e.update(['proxy-groups'], groups));
  }

  /// 就地替换整个节点（保持位置）。
  static YamlDoc updateProxy(
    YamlDoc doc,
    String name,
    Map<String, Object?> proxy,
  ) {
    final profile = Profile.from(doc);
    final entry = profile.proxy(name);
    if (entry == null) throw ConfigEditException('找不到节点：$name');
    final newName = _requireName(proxy);
    var next = doc.apply((e) => e.update(['proxies', entry.index], proxy));
    if (newName != name) {
      next = _rewriteReferences(next, name, newName);
    }
    return next;
  }

  /// 只改若干字段（值为 null 表示删除该键）。
  static YamlDoc patchProxy(
    YamlDoc doc,
    String name,
    Map<String, Object?> changes,
  ) {
    final profile = Profile.from(doc);
    final entry = profile.proxy(name);
    if (entry == null) throw ConfigEditException('找不到节点：$name');
    final next = doc.apply((e) {
      changes.forEach((key, value) {
        if (value == null) {
          if (entry.raw.containsKey(key)) {
            e.remove(['proxies', entry.index, key]);
          }
        } else {
          e.update(['proxies', entry.index, key], value);
        }
      });
    });
    final renamed = changes['name'];
    if (renamed is String && renamed != name) {
      return _rewriteReferences(next, name, renamed);
    }
    return next;
  }

  /// 删除节点，并从所有组的显式成员列表里摘掉。
  static YamlDoc deleteProxy(YamlDoc doc, String name) {
    var next = doc;
    final profile = Profile.from(doc);
    if (profile.proxy(name) == null) throw ConfigEditException('找不到节点：$name');
    for (final group in profile.groups) {
      if (group.members.contains(name)) {
        next = removeGroupMember(next, group.name, name);
      }
    }
    final fresh = Profile.from(next);
    final entry = fresh.proxy(name);
    if (entry != null) {
      next = next.apply((e) => e.remove(['proxies', entry.index]));
    }
    return next;
  }

  /// 改名，并同步所有引用（组成员、规则目标）。
  static YamlDoc renameProxy(YamlDoc doc, String oldName, String newName) {
    if (oldName == newName) return doc;
    final profile = Profile.from(doc);
    if (profile.proxy(oldName) == null) {
      throw ConfigEditException('找不到节点：$oldName');
    }
    if (profile.proxy(newName) != null) {
      throw ConfigEditException('名字已存在：$newName');
    }
    final entry = profile.proxy(oldName)!;
    final next = doc.apply(
      (e) => e.update(['proxies', entry.index, 'name'], newName),
    );
    return _rewriteReferences(next, oldName, newName);
  }

  // ---------------------------------------------------------------- 策略组

  static YamlDoc addGroup(
    YamlDoc doc,
    Map<String, Object?> group, {
    List<String> members = const [],
  }) {
    final name = _requireName(group);
    if (Profile.from(doc).group(name) != null) {
      throw ConfigEditException('策略组已存在：$name');
    }
    final map = <String, Object?>{...group};
    if (members.isNotEmpty) {
      final existing = map['proxies'];
      map['proxies'] = <Object?>[if (existing is List) ...existing, ...members];
    }
    final current = doc.plainAt(['proxy-groups']);
    if (current is List && current.isNotEmpty) {
      return doc.apply((e) => e.appendToList(['proxy-groups'], map));
    }
    // 空列表（例如 `proxy-groups: []`）用 update 才能保持块状风格；
    // appendToList 会把整个列表改写成 flow 风格 `[{...}]`。
    return doc.apply((e) => e.update(['proxy-groups'], <Object?>[map]));
  }

  /// 组改名，并同步所有引用（规则目标、其它组的成员列表）。
  static YamlDoc renameGroup(YamlDoc doc, String oldName, String newName) {
    if (oldName == newName) return doc;
    final profile = Profile.from(doc);
    final group = profile.group(oldName);
    if (group == null) throw ConfigEditException('找不到策略组：$oldName');
    if (profile.group(newName) != null) {
      throw ConfigEditException('策略组已存在：$newName');
    }
    final next = doc.apply(
      (e) => e.update(['proxy-groups', group.index, 'name'], newName),
    );
    return _rewriteReferences(next, oldName, newName);
  }

  static YamlDoc deleteGroup(YamlDoc doc, String name) {
    final profile = Profile.from(doc);
    final group = profile.group(name);
    if (group == null) throw ConfigEditException('找不到策略组：$name');
    return doc.apply((e) => e.remove(['proxy-groups', group.index]));
  }

  static YamlDoc patchGroup(
    YamlDoc doc,
    String name,
    Map<String, Object?> changes,
  ) {
    final profile = Profile.from(doc);
    final group = profile.group(name);
    if (group == null) throw ConfigEditException('找不到策略组：$name');
    return doc.apply((e) {
      changes.forEach((key, value) {
        if (value == null) {
          if (group.raw.containsKey(key)) {
            e.remove(['proxy-groups', group.index, key]);
          }
        } else {
          e.update(['proxy-groups', group.index, key], value);
        }
      });
    });
  }

  /// 整体重写某个组的显式成员列表（顺序即最终顺序）。
  ///
  /// 写回前统一归一化为「代理节点 → 其它成员 → DIRECT → REJECT」，
  /// 与 UI、mihomo 的 select 语义保持一致。
  static YamlDoc setGroupMembers(
    YamlDoc doc,
    String groupName,
    List<String> members,
  ) {
    final profile = Profile.from(doc);
    final group = profile.group(groupName);
    if (group == null) throw ConfigEditException('找不到策略组：$groupName');
    final ordered = normalizeMemberOrder(
      members,
      proxyOrder: _proxyOrder(profile),
    );
    return _writeMembers(doc, group, ordered);
  }

  static YamlDoc _writeMembers(
    YamlDoc doc,
    GroupEntry group,
    List<String> members,
  ) {
    final value = <Object?>[...members];
    if (group.raw.containsKey('proxies') || value.isNotEmpty) {
      return doc.apply(
        (e) => e.update(['proxy-groups', group.index, 'proxies'], value),
      );
    }
    return doc;
  }

  /// 成员增删后若顺序不符合规范（例如旧配置把 DIRECT 放在节点前面），
  /// 就地重写一次；顺序已正确时不产生任何 YAML 改动。
  static YamlDoc _normalizeMembers(YamlDoc doc, String groupName) {
    final profile = Profile.from(doc);
    final group = profile.group(groupName);
    // relay 的 members 顺序就是链式顺序，任何规范化都会打乱链路。
    if (group == null || group.type == 'relay' || group.members.length < 2) {
      return doc;
    }
    final ordered = normalizeMemberOrder(
      group.members,
      proxyOrder: _proxyOrder(profile),
    );
    if (_sameMembers(ordered, group.members)) return doc;
    return _writeMembers(doc, group, ordered);
  }

  static YamlDoc addGroupMember(
    YamlDoc doc,
    String groupName,
    String member, {
    bool missingGroupOk = false,
    int? at,
  }) {
    final profile = Profile.from(doc);
    final group = profile.group(groupName);
    if (group == null) {
      if (missingGroupOk) return doc;
      throw ConfigEditException('找不到策略组：$groupName');
    }
    if (group.members.contains(member)) {
      return _normalizeMembers(doc, groupName);
    }
    if (group.members.isNotEmpty && group.raw.containsKey('proxies')) {
      final memberAt =
          at ??
          normalizeMemberOrder(<String>[
            ...group.members,
            member,
          ], proxyOrder: _proxyOrder(profile)).indexOf(member);
      final next = doc.apply(
        (e) => e.insertIntoList(
          ['proxy-groups', group.index, 'proxies'],
          memberAt,
          member,
        ),
      );
      // `at` 是调用方明确指定的位置（如「插到内置出站之前」），保留其语义；
      // 其余插入才按规范把内置出站压到末尾。
      return at == null ? _normalizeMembers(next, groupName) : next;
    }
    // 组里还没有成员（或没写 proxies 键）：整体写一次，保持块状风格；
    // 空 flow 列表插入单项会被 yaml_edit 写成 `proxies: [NAME]`。
    final next = doc.apply(
      (e) =>
          e.update(['proxy-groups', group.index, 'proxies'], <Object?>[member]),
    );
    return _normalizeMembers(next, groupName);
  }

  static YamlDoc removeGroupMember(
    YamlDoc doc,
    String groupName,
    String member,
  ) {
    final profile = Profile.from(doc);
    final group = profile.group(groupName);
    if (group == null) throw ConfigEditException('找不到策略组：$groupName');
    final index = group.members.indexOf(member);
    if (index < 0) return doc;
    final next = doc.apply(
      (e) => e.remove(['proxy-groups', group.index, 'proxies', index]),
    );
    return _normalizeMembers(next, groupName);
  }

  /// 把组内成员从 [from] 移动到 [to]（链式代理重排、组内拖拽）。
  ///
  /// 用「删一条 + 插一条」保持块状 YAML；relay 不做内置出站规范化，
  /// 因为成员顺序就是链路顺序。
  static YamlDoc moveGroupMember(
    YamlDoc doc,
    String groupName,
    int from,
    int to,
  ) {
    final profile = Profile.from(doc);
    final group = profile.group(groupName);
    if (group == null) throw ConfigEditException('找不到策略组：$groupName');
    final members = group.members;
    if (from < 0 || from >= members.length) {
      throw ConfigEditException('成员位置越界：$from');
    }
    if (to < 0 || to > members.length) {
      throw ConfigEditException('成员位置越界：$to');
    }
    if (from == to) return doc;
    final node = members[from];
    var next = doc.apply(
      (e) => e.remove(['proxy-groups', group.index, 'proxies', from]),
    );
    final target = from < to ? to - 1 : to;
    next = next.apply(
      (e) => e.insertIntoList(
        ['proxy-groups', group.index, 'proxies'],
        target,
        node,
      ),
    );
    return next;
  }

  /// 把节点从 A 组挪到 B 组（核心交互：跨组拖拽）。
  static YamlDoc moveMember(
    YamlDoc doc, {
    required String node,
    required String fromGroup,
    required String toGroup,
  }) {
    if (fromGroup == toGroup) return doc;
    var next = removeGroupMember(doc, fromGroup, node);
    next = addGroupMember(next, toGroup, node);
    return next;
  }

  // ---------------------------------------------------------------- 规则

  static List<String> ruleStrings(Profile profile) =>
      profile.rules.map((r) => r.raw).toList();

  static YamlDoc setRules(YamlDoc doc, List<String> rules) {
    final value = rules.map<Object?>((r) => r).toList();
    if (doc.has(['rules'])) {
      return doc.apply((e) => e.update(['rules'], value));
    }
    return doc.apply((e) => e.update(['rules'], value));
  }

  static YamlDoc addRule(YamlDoc doc, String rule, {int? at}) {
    final value = rule.trim();
    if (value.isEmpty) throw ConfigEditException('规则不能为空');
    final current = doc.plainAt(['rules']);
    if (current is! List || current.isEmpty) {
      // 缺键或 `rules: []`：整体写入，块状风格。
      return doc.apply((e) => e.update(['rules'], <Object?>[value]));
    }
    final profile = Profile.from(doc);
    final index = at ?? profile.rules.length;
    return doc.apply((e) => e.insertIntoList(['rules'], index, value));
  }

  static YamlDoc updateRule(YamlDoc doc, int index, String rule) {
    final profile = Profile.from(doc);
    _checkRuleIndex(profile, index);
    return doc.apply((e) => e.update(['rules', index], rule.trim()));
  }

  static YamlDoc deleteRule(YamlDoc doc, int index) {
    final profile = Profile.from(doc);
    _checkRuleIndex(profile, index);
    return doc.apply((e) => e.remove(['rules', index]));
  }

  /// 把第 [from] 条规则移动到最终位置 [to]。
  static YamlDoc moveRule(YamlDoc doc, int from, int to) {
    final profile = Profile.from(doc);
    _checkRuleIndex(profile, from);
    if (to < 0 || to >= profile.rules.length) {
      throw ConfigEditException('规则位置越界：$to');
    }
    if (from == to) return doc;
    final rule = profile.rules[from].raw;
    var next = doc.apply((e) => e.remove(['rules', from]));
    final target = from < to ? to : to;
    next = next.apply((e) => e.insertIntoList(['rules'], target, rule));
    return next;
  }

  // ---------------------------------------------------------------- 顶层配置

  static YamlDoc setTop(YamlDoc doc, String key, Object? value) {
    return doc.apply((e) => e.update([key], value));
  }

  /// 任意路径写入（路径必须已存在，或用 setAtOrCreate 逐段补建）。
  static YamlDoc setAt(YamlDoc doc, List<Object?> path, Object? value) {
    return doc.apply((e) => e.update(path, value));
  }

  /// 任意路径写入，**缺失的中间映射会自动补建**。
  ///
  /// 例：配置里没有 `tun:` 段时写 `tun.stack`，会整段建出 `tun: {stack: system}`
  /// （yaml_edit 的 `update` 要求父节点存在，直接写会抛 Invalid path）。
  /// 若某一层已存在但不是映射（例如写着 `tun: false`），不会静默覆盖，而是抛异常。
  static YamlDoc setAtOrCreate(YamlDoc doc, List<Object?> path, Object? value) {
    if (path.isEmpty) {
      throw ConfigEditException('路径不能为空');
    }
    for (var i = 1; i < path.length; i++) {
      final prefix = path.sublist(0, i);
      final existing = doc.plainAt(prefix);
      if (existing is Map) continue;
      if (existing != null) {
        throw ConfigEditException(
          '${prefix.join('.')} 已经不是映射，无法写入 ${path.join('.')}',
        );
      }
      final nested = _nest(path.sublist(i), value);
      return doc.apply((e) => e.update(prefix, nested));
    }
    return doc.apply((e) => e.update(path, value));
  }

  static Map<String, Object?> _nest(List<Object?> rest, Object? value) {
    Object? out = value;
    for (var i = rest.length - 1; i >= 0; i--) {
      out = <String, Object?>{'${rest[i]}': out};
    }
    return (out as Map).cast<String, Object?>();
  }

  static YamlDoc removeTop(YamlDoc doc, String key) {
    if (!doc.has([key])) return doc;
    return doc.apply((e) => e.remove([key]));
  }

  // ---------------------------------------------------------------- 内部

  static YamlDoc _appendProxy(YamlDoc doc, Map<String, Object?> proxy) {
    final name = _requireName(proxy);
    final profile = Profile.from(doc);
    if (profile.proxy(name) != null) {
      throw ConfigEditException('节点名已存在：$name');
    }
    final current = doc.plainAt(['proxies']);
    if (current is List && current.isNotEmpty) {
      return doc.apply((e) => e.appendToList(['proxies'], proxy));
    }
    // `proxies: []` / 缺键：用 update 才会输出块状列表。
    return doc.apply((e) => e.update(['proxies'], <Object?>[proxy]));
  }

  static String _requireName(Map<String, Object?> node) {
    final name = node['name'];
    if (name is! String || name.trim().isEmpty) {
      throw ConfigEditException('节点缺少 name');
    }
    return name;
  }

  static void _checkRuleIndex(Profile profile, int index) {
    if (index < 0 || index >= profile.rules.length) {
      throw ConfigEditException('规则不存在：$index');
    }
  }

  /// 把 [oldName] 在组成员与规则目标里的引用改成 [newName]。
  static YamlDoc _rewriteReferences(
    YamlDoc doc,
    String oldName,
    String newName,
  ) {
    var next = doc;
    var profile = Profile.from(next);
    // 组成员：从后往前删/插，避免下标漂移。
    for (final group in profile.groups) {
      for (var i = group.members.length - 1; i >= 0; i--) {
        if (group.members[i] != oldName) continue;
        final liveGroup = Profile.from(next).group(group.name);
        if (liveGroup == null) continue;
        next = next.apply(
          (e) => e.update([
            'proxy-groups',
            liveGroup.index,
            'proxies',
            i,
          ], newName),
        );
      }
    }
    // 规则目标
    profile = Profile.from(next);
    for (final rule in profile.rules) {
      if (rule.target != oldName) continue;
      final parts = rule.raw.split(',');
      final at = rule.targetIndex;
      if (at >= parts.length) continue;
      parts[at] = newName;
      final rebuilt = parts.join(',');
      next = next.apply((e) => e.update(['rules', rule.index], rebuilt));
    }
    return next;
  }
}
