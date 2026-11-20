import '../core/edit/config_ops.dart';
import '../core/yaml/yaml_doc.dart';

/// 把用户配置改造成"内核可直接跑"的运行配置。
///
/// 用户的配置是要落到手机上给别人看的（保留注释、顺序、未知字段），
/// 而运行期内核需要额外的一些键（external-controller / tun.file-descriptor /
/// dns 等）。两者分开：用户文件不动，运行时写一份派生文件到缓存目录。
class RuntimeConfig {
  const RuntimeConfig._();

  /// 默认控制器地址：只监听回环，外部访问需要 secret。
  static const String defaultController = '127.0.0.1:9090';

  static const String defaultStack = 'gvisor';

  /// TUN 网卡地址由**内核**决定，而不是配置里的 `inet4-address`。
  ///
  /// mihomo 的 `parseTun()`（`config/config.go`）完全忽略用户写的 `inet4-address`，
  /// 而是把 `dns.fake-ip-range` 的地址截成 `/30` 当 tun 地址（默认
  /// `198.18.0.1/16` → `198.18.0.1/30`）。`system` / `mixed` 栈要在网卡上 bind
  /// 这个地址，所以 `VpnService.Builder` 必须配同一个地址；`gVisor` 只读写 fd、
  /// 不看地址，因此以前地址不一致时只有它"能用"。
  ///
  /// 这里返回内核会算出来的那个地址，交给 Kotlin 侧建网卡，避免两边再对不上。
  static String tunAddressFor(YamlDoc doc) {
    final raw = doc.plainAt(['dns', 'fake-ip-range']);
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) return '198.18.0.1/30';
    final addr = text.contains('/')
        ? text.substring(0, text.indexOf('/'))
        : text;
    if (addr.isEmpty) return '198.18.0.1/30';
    return '$addr/30';
  }

  static const String tunAddress6 = 'fdfe:dcba:9876::1/126';

  /// 本地 HTTP 代理端口：运行配置里的 `mixed-port`，缺省 7890。
  ///
  /// 下载测速要经这个端口把流量交给内核，所以必须和运行 YAML 用的是同一个值。
  static int proxyPortFor(YamlDoc doc) {
    final raw = doc.plainAt(['mixed-port']);
    if (raw is num) {
      final port = raw.toInt();
      if (port > 0 && port <= 65535) return port;
    }
    return 7890;
  }

  /// 默认用明文 UDP DNS：DoH 在内核里走 Go 自己的 TLS 栈，某些 ROM / 模拟器
  /// 上会匹配不到系统根证书（实测 `x509: certificate signed by unknown
  /// authority`），一旦 DNS 全废整条链路就废；UDP 53 由 mihomo 自己的
  /// outbound 直连发出，最稳。想用 DoH 的用户可以在配置里自己写 `dns` 段。
  static const List<Object?> _defaultNameserver = ['223.5.5.5', '119.29.29.29'];

  /// 解析 DNS 服务器域名本身用的引导 DNS（这里都是 IP，留作兜底说明）。
  static const List<Object?> _defaultDefaultNameserver = [
    '223.5.5.5',
    '119.29.29.29',
  ];

  /// 生成运行配置文本。
  ///
  /// [tunFileDescriptor] > 0 时写入 `tun.file-descriptor`（Android VpnService
  /// 拿到的 TUN fd）；传 0 表示不用 TUN（桌面端调试 / 只开 mixed-port）。
  static String buildRuntimeYaml(
    YamlDoc doc, {
    required int tunFileDescriptor,
    String controller = defaultController,
    String? secret,
    bool allowLan = false,
    bool ensureDns = true,
  }) {
    var next = doc;

    // mihomo 1.10 起不再支持 `type: relay`，链式代理要在运行配置里展开成
    // dialer-proxy 链。只改派生文件：用户配置与 sidecar 保持原样。
    next = _expandRelayGroups(next);

    next = _set(next, ['external-controller'], controller);
    if (secret != null && secret.isNotEmpty) {
      next = _set(next, ['secret'], secret);
    }
    next = _set(next, ['allow-lan'], allowLan);
    next = _setIfAbsent(next, ['mixed-port'], 7890);
    next = _setIfAbsent(next, ['log-level'], 'info');
    next = _setIfAbsent(next, ['mode'], 'rule');

    if (tunFileDescriptor > 0) {
      // fd 由系统 VpnService 提供：v4 地址由内核从 fake-ip-range 推导（写
      // inet4-address 也没用，见 tunAddressFor 的注释），所以这里不写；v6 地址
      // 内核是认的，得和 VpnService 配的一致。
      final configuredMtu = doc.plainAt(['tun', 'mtu']);
      final effectiveMtu = configuredMtu is num ? configuredMtu.toInt() : null;
      final configuredStack = doc.plainAt(['tun', 'stack']);
      final stack =
          configuredStack is String && configuredStack.trim().isNotEmpty
          ? configuredStack.trim().toLowerCase()
          : defaultStack;
      final ipv6 = doc.plainAt(['ipv6']);
      final tunOptions = <String, Object?>{
        'enable': true,
        'stack': stack,
        'file-descriptor': tunFileDescriptor,
        'auto-route': false,
        'auto-detect-interface': false,
        'dns-hijack': <Object?>['any:53'],
      };
      if (ipv6 == true) {
        tunOptions['inet6-address'] = <Object?>[tunAddress6];
      }
      // 用户没写 mtu 就交给内核默认值，不要强行塞一个数进去。
      if (effectiveMtu != null) tunOptions['mtu'] = effectiveMtu;
      next = _set(next, ['tun'], tunOptions);
      if (ensureDns) {
        next = _ensureDns(next);
        // 不覆盖用户显式写的 `dns.enable`：TUN 下关掉 DNS 是用户的选择，
        // 只在完全没写 dns 段时补默认值（见 `_ensureDns`）。
      }
    } else {
      // 仅代理端口模式：显式关掉 TUN，避免内核去读一个不存在的 fd。
      next = _set(next, ['tun', 'enable'], false);
    }

    return next.text;
  }

  /// 把 `proxy-groups` 里的 `type: relay` 展开成 dialer-proxy 链。
  ///
  /// mihomo 1.10 移除了 relay 类型（fatal `unsupported type: ... relay type
  /// was removed, please using dialer-proxy instead`）。这里只在运行配置里
  /// 改写：成员 A→B→C 生成隐藏代理 `__chain_<组>_1..3`，后者用
  /// `dialer-proxy` 指向前者；原组名改成 `select` 且只保留最后一级，
  /// 选中即整条链。用户文件与 sidecar 完全不动。
  static YamlDoc _expandRelayGroups(YamlDoc doc) {
    final rawGroups = doc.plainAt(['proxy-groups']);
    if (rawGroups is! List || rawGroups.isEmpty) return doc;
    final rawProxies = doc.plainAt(['proxies']);
    final proxies = <Object?>[
      if (rawProxies is List)
        for (final item in rawProxies)
          item is Map ? YamlDoc.toPlainMap(item) : item,
    ];
    final byName = <String, Map<String, Object?>>{};
    for (final item in proxies) {
      if (item is Map) {
        final name = item['name'];
        if (name is String) byName[name] = YamlDoc.toPlainMap(item);
      }
    }
    var changed = false;
    final hidden = <Object?>[];
    final groups = <Object?>[];
    for (final raw in rawGroups) {
      if (raw is! Map) {
        groups.add(raw);
        continue;
      }
      final group = YamlDoc.toPlainMap(raw);
      if ('${group['type'] ?? ''}'.trim().toLowerCase() != 'relay') {
        groups.add(group);
        continue;
      }
      changed = true;
      final rawMembers = group['proxies'];
      final members = <String>[
        if (rawMembers is List)
          for (final member in rawMembers)
            if ('$member'.isNotEmpty && byName.containsKey('$member'))
              '$member',
      ];
      final groupName = '${group['name'] ?? 'relay'}';
      if (members.isEmpty) {
        // 空 relay 组没有任何可跑的东西，收敛成 DIRECT，至少不 fatal。
        groups.add(<String, Object?>{
          'name': groupName,
          'type': 'select',
          'proxies': <Object?>['DIRECT'],
        });
        continue;
      }
      if (members.length == 1) {
        // 单节点不需要链：直接 select 该节点，少一层隐藏代理。
        groups.add(<String, Object?>{
          'name': groupName,
          'type': 'select',
          'proxies': <Object?>[members.first],
        });
        continue;
      }
      final chain = <String>[];
      for (var i = 0; i < members.length; i++) {
        var chainName = '__chain_${groupName}_${i + 1}';
        while (byName.containsKey(chainName)) {
          chainName = '${chainName}_';
        }
        final proxy = <String, Object?>{
          ...byName[members[i]]!,
          'name': chainName,
        };
        if (i > 0) proxy['dialer-proxy'] = chain[i - 1];
        hidden.add(proxy);
        byName[chainName] = proxy;
        chain.add(chainName);
      }
      // 单节点 relay 也走 select，只是没有 dialer-proxy 前缀链。
      groups.add(<String, Object?>{
        'name': groupName,
        'type': 'select',
        'proxies': <Object?>[chain.last],
      });
    }
    if (!changed) return doc;
    var next = doc;
    next = ConfigOps.setAt(next, ['proxies'], <Object?>[...proxies, ...hidden]);
    next = ConfigOps.setAt(next, ['proxy-groups'], groups);
    return next;
  }

  /// 保证 DNS 段存在且为 fake-ip（TUN 下最稳），但**不覆盖**用户已写的值。
  static YamlDoc _ensureDns(YamlDoc doc) {
    final dns = doc.plainAt(['dns']);
    if (dns is Map) {
      var next = doc;
      next = _setIfAbsent(next, ['dns', 'enable'], true);
      next = _setIfAbsent(next, ['dns', 'enhanced-mode'], 'fake-ip');
      next = _setIfAbsent(next, ['dns', 'fake-ip-range'], '198.18.0.1/16');
      next = _setIfAbsent(next, ['dns', 'nameserver'], _defaultNameserver);
      next = _setIfAbsent(next, [
        'dns',
        'default-nameserver',
      ], _defaultDefaultNameserver);
      return next;
    }
    return _set(
      doc,
      ['dns'],
      <String, Object?>{
        'enable': true,
        'enhanced-mode': 'fake-ip',
        'fake-ip-range': '198.18.0.1/16',
        'nameserver': _defaultNameserver,
        'default-nameserver': _defaultDefaultNameserver,
      },
    );
  }

  /// 值不同才写（保持用户文本零改动）。
  ///
  /// 中间层缺失时会把整段建出来：yaml_edit 的 update 要求父节点已存在，
  /// 而运行配置经常需要往一个还不存在的段里写键（例如没有 tun 段的配置）。
  static YamlDoc _set(YamlDoc doc, List<Object?> path, Object? value) {
    final current = doc.plainAt(path);
    if (_deepEquals(current, value)) return doc;
    if (path.length > 1 && doc.plainAt([path.first]) is! Map) {
      return ConfigOps.setAt(
        doc,
        [path.first],
        <String, Object?>{'${path[1]}': value},
      );
    }
    return ConfigOps.setAt(doc, path, value);
  }

  /// 路径不存在时才写。
  static YamlDoc _setIfAbsent(YamlDoc doc, List<Object?> path, Object? value) {
    if (doc.has(path)) return doc;
    return ConfigOps.setAt(doc, path, value);
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in b.keys) {
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
