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

    next = _set(next, ['external-controller'], controller);
    if (secret != null && secret.isNotEmpty) {
      next = _set(next, ['secret'], secret);
    }
    next = _set(next, ['allow-lan'], allowLan);
    next = _setIfAbsent(next, ['mixed-port'], 7890);
    next = _setIfAbsent(next, ['log-level'], 'info');
    next = _setIfAbsent(next, ['mode'], 'rule');

    if (tunFileDescriptor > 0) {
      // 栈固定 gVisor：fd 由系统 VpnService 提供、地址也由系统配好，sing-tun 的
      // system / mixed 栈要自己给网卡套地址再 bind，实测报
      //   listen tcp4 198.18.0.1:0: bind: cannot assign requested address
      // 只有 gVisor 能在「别人给的 fd」上跑。MTU 仍以用户配置为准。
      final configuredMtu = doc.plainAt(['tun', 'mtu']);
      final effectiveMtu = configuredMtu is num ? configuredMtu.toInt() : null;
      final tunOptions = <String, Object?>{
        'enable': true,
        'stack': defaultStack,
        'file-descriptor': tunFileDescriptor,
        'auto-route': false,
        'auto-detect-interface': false,
        'dns-hijack': <Object?>['any:53'],
      };
      // 用户没写 mtu 就交给内核默认值，不要强行塞一个数进去。
      if (effectiveMtu != null) tunOptions['mtu'] = effectiveMtu;
      next = _set(next, ['tun'], tunOptions);
      if (ensureDns) next = _ensureDns(next);
    } else {
      // 仅代理端口模式：显式关掉 TUN，避免内核去读一个不存在的 fd。
      next = _set(next, ['tun', 'enable'], false);
    }

    return next.text;
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
