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
  });

  final ProxyMode proxyMode;
  final AppRouteMode routeMode;
  final List<String> routePackages;

  /// 0 表示关闭自动更新。
  final int autoUpdateHours;

  /// 开机自启（需要系统允许后台启动，当前仅记录开关）。
  final bool launchOnBoot;

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    ProxyMode? proxyMode,
    AppRouteMode? routeMode,
    List<String>? routePackages,
    int? autoUpdateHours,
    bool? launchOnBoot,
  }) {
    return AppSettings(
      proxyMode: proxyMode ?? this.proxyMode,
      routeMode: routeMode ?? this.routeMode,
      routePackages: routePackages ?? this.routePackages,
      autoUpdateHours: autoUpdateHours ?? this.autoUpdateHours,
      launchOnBoot: launchOnBoot ?? this.launchOnBoot,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'proxyMode': proxyMode.id,
    'routeMode': routeMode.id,
    'routePackages': routePackages,
    'autoUpdateHours': autoUpdateHours,
    'launchOnBoot': launchOnBoot,
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
    );
  }

  /// 传给 Android 侧 `start` 的参数。
  Map<String, Object?> toStartArgs() => <String, Object?>{
    'proxyMode': proxyMode.id,
    'routeMode': routeMode.id,
    'routeApps': routePackages,
  };
}
