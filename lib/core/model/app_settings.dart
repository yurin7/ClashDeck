/// 代理接管方式。
///
/// - [tun]：VpnService 建 TUN，全部流量走内核（默认，手机上的常规用法）；
/// - [portOnly]：不建 VPN，只开 mixed-port（7890）让别的 App 手动指向它，
///   或者只在浏览器/终端里用。这需要用户自己配置代理，不接管系统流量。
enum ProxyMode { tun, portOnly }

/// 分应用代理的方式。
enum AppRouteMode {
  /// 所有 App 都走代理，只排除自己（默认）。
  all,

  /// 只有选中的 App 走代理。
  allowList,

  /// 选中的 App 不走代理。
  blockList,
}

extension ProxyModeX on ProxyMode {
  String get id => this == ProxyMode.tun ? 'tun' : 'port';

  String get label => this == ProxyMode.tun ? 'TUN 模式' : '仅代理端口';

  String get description => this == ProxyMode.tun
      ? '建立 VPN 接管全部流量，需要系统授权'
      : '不接管流量，只开 mixed-port 7890 供其它应用手动使用';

  static ProxyMode fromId(Object? id) =>
      id == 'port' ? ProxyMode.portOnly : ProxyMode.tun;
}

extension AppRouteModeX on AppRouteMode {
  String get id => switch (this) {
    AppRouteMode.all => 'all',
    AppRouteMode.allowList => 'allow',
    AppRouteMode.blockList => 'block',
  };

  String get label => switch (this) {
    AppRouteMode.all => '全部应用',
    AppRouteMode.allowList => '仅选中的应用',
    AppRouteMode.blockList => '排除选中的应用',
  };

  static AppRouteMode fromId(Object? id) => switch (id) {
    'allow' => AppRouteMode.allowList,
    'block' => AppRouteMode.blockList,
    _ => AppRouteMode.all,
  };
}

/// 应用级设置（不写进 YAML 的部分）。
///
/// 为什么分开：`proxyMode` / 分应用名单 / 自动更新这些是**本 App 的行为**，
/// 写进 YAML 会让内核和别家客户端看到未知键；而 TUN 栈、DNS 这些是内核配置，
/// 应该落在 YAML 里让用户看得见、也能带走。
class AppSettings {
  const AppSettings({
    this.proxyMode = ProxyMode.tun,
    this.routeMode = AppRouteMode.all,
    this.routePackages = const <String>[],
    this.autoUpdateHours = 0,
    this.launchOnBoot = false,
    this.autoSave = false,
    this.globalNode,
    this.groupNodes = const <String, String>{},
  });

  /// copyWith 里区分「没给这个参数」和「明确要设成 null」。
  static const Object _unset = Object();

  final ProxyMode proxyMode;
  final AppRouteMode routeMode;
  final List<String> routePackages;

  /// 0 表示关闭自动更新。
  final int autoUpdateHours;

  /// 开机自启（需要系统允许后台启动，当前仅记录开关）。
  final bool launchOnBoot;

  /// 返回上一级时，若当前配置没有校验错误，就自动保存。
  final bool autoSave;

  /// 「全局」模式下选定的出口（节点名或策略组名）。
  ///
  /// 存在 sidecar 里而不是写 YAML：它表达的是「用户想让 GLOBAL 走哪个」，
  /// 内核没起来时也能选、能存，等内核起来再应用（`GLOBAL` 组是内核内置的）。
  final String? globalNode;

  /// 「组 → 组内节点」：用户在概览里把 GLOBAL 指向某个组时，顺手选好的组内节点。
  ///
  /// 内核的组选择是运行期状态（不落在 YAML 里），所以也存 sidecar：起内核后
  /// 先把每个组切到记下的节点，再把 GLOBAL 切到 `globalNode`，顺序还原用户看到的画面。
  final Map<String, String> groupNodes;

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    ProxyMode? proxyMode,
    AppRouteMode? routeMode,
    List<String>? routePackages,
    int? autoUpdateHours,
    bool? launchOnBoot,
    bool? autoSave,
    Object? globalNode = _unset,
    Map<String, String>? groupNodes,
  }) {
    return AppSettings(
      proxyMode: proxyMode ?? this.proxyMode,
      routeMode: routeMode ?? this.routeMode,
      routePackages: routePackages ?? this.routePackages,
      autoUpdateHours: autoUpdateHours ?? this.autoUpdateHours,
      launchOnBoot: launchOnBoot ?? this.launchOnBoot,
      autoSave: autoSave ?? this.autoSave,
      globalNode: identical(globalNode, _unset)
          ? this.globalNode
          : globalNode as String?,
      groupNodes: groupNodes ?? this.groupNodes,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'proxyMode': proxyMode.id,
    'routeMode': routeMode.id,
    'routePackages': routePackages,
    'autoUpdateHours': autoUpdateHours,
    'launchOnBoot': launchOnBoot,
    'autoSave': autoSave,
    'globalNode': globalNode,
    'groupNodes': groupNodes,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    final packages = json['routePackages'];
    return AppSettings(
      proxyMode: ProxyModeX.fromId(json['proxyMode']),
      routeMode: AppRouteModeX.fromId(json['routeMode']),
      routePackages: packages is List
          ? packages.map((e) => '$e').toList(growable: false)
          : const <String>[],
      autoUpdateHours: (json['autoUpdateHours'] as num?)?.toInt() ?? 0,
      launchOnBoot: json['launchOnBoot'] == true,
      // 缺省为 false：老版本存下来的 app 段没有这个键时，按「不自动保存」处理。
      autoSave: json['autoSave'] as bool? ?? false,
      globalNode: switch (json['globalNode']) {
        final String name when name.isNotEmpty => name,
        _ => null,
      },
      groupNodes: switch (json['groupNodes']) {
        final Map<Object?, Object?> map => {
          for (final entry in map.entries)
            if (entry.key is String && entry.value is String)
              entry.key! as String: entry.value! as String,
        },
        _ => const <String, String>{},
      },
    );
  }

  /// 传给 Android 侧 `start` 的参数。
  Map<String, Object?> toStartArgs() => <String, Object?>{
    'proxyMode': proxyMode.id,
    'routeMode': routeMode.id,
    'routeApps': routePackages,
  };
}
