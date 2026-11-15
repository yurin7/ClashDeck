import 'field_spec.dart';

/// 支持的节点协议类型（与 mihomo 配置里的 `type` 取值一致）。
///
/// 这里的顺序也是新增节点时下拉框的顺序。
const List<String> kSupportedProxyTypes = <String>[
  'vless',
  'vmess',
  'trojan',
  'ss',
  'hysteria2',
  'tuic',
  'wireguard',
  'socks5',
  'http',
  'snell',
  'ssh',
  'anytls',
  'ssr',
];

// ---------------------------------------------------------------------------
// 公共字段（每个节点都会出现）
// ---------------------------------------------------------------------------

const List<String> _ipVersionOptions = <String>[
  'dual',
  'ipv4',
  'ipv6',
  'ipv4-prefer',
  'ipv6-prefer',
];

const List<String> _clientFingerprintOptions = <String>[
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  '360',
  'qq',
  'random',
];

const List<String> _networkOptions = <String>[
  'ws',
  'http',
  'h2',
  'grpc',
  'tcp',
];

/// VLESS 上游还支持 `xhttp` 传输（与 `xhttp-opts` 对应）。
const List<String> _vlessNetworkOptions = <String>[
  'ws',
  'http',
  'h2',
  'grpc',
  'tcp',
  'xhttp',
];

const FieldSpec _name = FieldSpec(
  key: 'name',
  labelZh: '名称',
  kind: FieldKind.string,
  group: FieldGroup.basic,
  required: true,
  help: '配置内唯一，用于分组与规则引用',
);

const FieldSpec _server = FieldSpec(
  key: 'server',
  labelZh: '服务器',
  kind: FieldKind.string,
  group: FieldGroup.basic,
  required: true,
  help: '域名或 IP 地址',
);

const FieldSpec _port = FieldSpec(
  key: 'port',
  labelZh: '端口',
  kind: FieldKind.int,
  group: FieldGroup.basic,
  required: true,
  help: '1-65535',
);

const FieldSpec _udp = FieldSpec(
  key: 'udp',
  labelZh: 'UDP 转发',
  kind: FieldKind.bool,
  group: FieldGroup.protocol,
  help: '允许该节点转发 UDP 流量',
);

/// 各协议共有的进阶网络选项（BasicOption）。
const List<FieldSpec> _commonTail = <FieldSpec>[
  FieldSpec(
    key: 'tfo',
    labelZh: 'TCP Fast Open',
    kind: FieldKind.bool,
    group: FieldGroup.advanced,
    advanced: true,
    help: '减少 TCP 握手延迟，需服务端支持',
  ),
  FieldSpec(
    key: 'mptcp',
    labelZh: '多路径 TCP',
    kind: FieldKind.bool,
    group: FieldGroup.advanced,
    advanced: true,
    help: '需系统与服务端同时支持',
  ),
  FieldSpec(
    key: 'interface-name',
    labelZh: '绑定网卡',
    kind: FieldKind.string,
    group: FieldGroup.advanced,
    advanced: true,
    help: '指定出站网卡名，Android 通常留空',
  ),
  FieldSpec(
    key: 'ip-version',
    labelZh: 'IP 版本',
    kind: FieldKind.enumChoice,
    group: FieldGroup.basic,
    options: _ipVersionOptions,
    defaultValue: 'dual',
    help: '优先使用的 IP 协议族',
  ),
  FieldSpec(
    key: 'routing-mark',
    labelZh: '路由标记',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: 'Linux fwmark，Android 一般留空',
  ),
  FieldSpec(
    key: 'dialer-proxy',
    labelZh: '前置代理',
    kind: FieldKind.string,
    group: FieldGroup.advanced,
    advanced: true,
    help: '通过指定节点或分组建立连接，填名称',
  ),
];

// ---------------------------------------------------------------------------
// TLS 相关字段
// ---------------------------------------------------------------------------

const FieldSpec _tls = FieldSpec(
  key: 'tls',
  labelZh: '启用 TLS',
  kind: FieldKind.bool,
  group: FieldGroup.tls,
  help: '加密传输，需与服务端一致',
);

const FieldSpec _sni = FieldSpec(
  key: 'sni',
  labelZh: 'SNI / 域名',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  help: 'TLS 握手使用的域名，留空则使用 server',
);

const FieldSpec _sniIfTls = FieldSpec(
  key: 'sni',
  labelZh: 'SNI / 域名',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'TLS 握手使用的域名，留空则使用 server',
);

const FieldSpec _servernameIfTls = FieldSpec(
  key: 'servername',
  labelZh: 'SNI / 域名',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'TLS 握手使用的域名，留空则使用 server',
);

const FieldSpec _alpn = FieldSpec(
  key: 'alpn',
  labelZh: 'ALPN 协议',
  kind: FieldKind.stringList,
  group: FieldGroup.tls,
  help: '如 h2, http/1.1；留空由服务端协商',
);

const FieldSpec _alpnIfTls = FieldSpec(
  key: 'alpn',
  labelZh: 'ALPN 协议',
  kind: FieldKind.stringList,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '如 h2, http/1.1；留空由服务端协商',
);

const FieldSpec _skipCert = FieldSpec(
  key: 'skip-cert-verify',
  labelZh: '跳过证书验证',
  kind: FieldKind.bool,
  group: FieldGroup.tls,
  help: '自签证书时开启，会降低安全性',
);

const FieldSpec _skipCertIfTls = FieldSpec(
  key: 'skip-cert-verify',
  labelZh: '跳过证书验证',
  kind: FieldKind.bool,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '自签证书时开启，会降低安全性',
);

const FieldSpec _nameCert = FieldSpec(
  key: 'name-cert-verify',
  labelZh: '证书域名校验',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  help: '额外校验证书中的主机名，一般留空',
);

const FieldSpec _nameCertIfTls = FieldSpec(
  key: 'name-cert-verify',
  labelZh: '证书域名校验',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '额外校验证书中的主机名，一般留空',
);

const FieldSpec _fingerprint = FieldSpec(
  key: 'fingerprint',
  labelZh: '证书指纹',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  help: '固定证书 SHA-256 指纹，防止中间人攻击',
);

const FieldSpec _fingerprintIfTls = FieldSpec(
  key: 'fingerprint',
  labelZh: '证书指纹',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '固定证书 SHA-256 指纹，防止中间人攻击',
);

const FieldSpec _certificate = FieldSpec(
  key: 'certificate',
  labelZh: '客户端证书',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  help: 'PEM 格式证书内容',
);

const FieldSpec _certificateIfTls = FieldSpec(
  key: 'certificate',
  labelZh: '客户端证书',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'PEM 格式证书内容',
);

const FieldSpec _privateKeyTls = FieldSpec(
  key: 'private-key',
  labelZh: '客户端私钥',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  secret: true,
  help: 'PEM 格式私钥',
);

const FieldSpec _privateKeyTlsIfTls = FieldSpec(
  key: 'private-key',
  labelZh: '客户端私钥',
  kind: FieldKind.string,
  group: FieldGroup.tls,
  advanced: true,
  secret: true,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'PEM 格式私钥',
);

const FieldSpec _clientFingerprint = FieldSpec(
  key: 'client-fingerprint',
  labelZh: 'TLS 指纹',
  kind: FieldKind.enumChoice,
  group: FieldGroup.tls,
  options: _clientFingerprintOptions,
  defaultValue: 'chrome',
  help: '伪装 TLS 指纹，建议 chrome',
);

const FieldSpec _clientFingerprintIfTls = FieldSpec(
  key: 'client-fingerprint',
  labelZh: 'TLS 指纹',
  kind: FieldKind.enumChoice,
  group: FieldGroup.tls,
  options: _clientFingerprintOptions,
  defaultValue: 'chrome',
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '伪装 TLS 指纹，建议 chrome',
);

// ---------------------------------------------------------------------------
// 嵌套块入口字段（真正可见性由 visibleWhen 控制，子字段见 nested）
// ---------------------------------------------------------------------------

const FieldSpec _wsOptsField = FieldSpec(
  key: 'ws-opts',
  labelZh: 'WebSocket 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  visibleWhenKey: 'network',
  visibleWhenValue: 'ws',
  help: 'WebSocket 路径、请求头与早期数据',
);

const FieldSpec _grpcOptsField = FieldSpec(
  key: 'grpc-opts',
  labelZh: 'gRPC 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  visibleWhenKey: 'network',
  visibleWhenValue: 'grpc',
  help: 'gRPC 服务名与并发参数',
);

const FieldSpec _h2OptsField = FieldSpec(
  key: 'h2-opts',
  labelZh: 'HTTP/2 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  visibleWhenKey: 'network',
  visibleWhenValue: 'h2',
  help: 'HTTP/2 伪装参数',
);

const FieldSpec _httpOptsField = FieldSpec(
  key: 'http-opts',
  labelZh: 'HTTP 伪装设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  visibleWhenKey: 'network',
  visibleWhenValue: 'http',
  help: 'HTTP 伪装参数',
);

const FieldSpec _xhttpOptsField = FieldSpec(
  key: 'xhttp-opts',
  labelZh: 'XHTTP 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  visibleWhenKey: 'network',
  visibleWhenValue: 'xhttp',
  help: 'XHTTP 实验传输参数',
);

const FieldSpec _wsHeadersField = FieldSpec(
  key: 'ws-headers',
  labelZh: 'WebSocket 请求头',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  advanced: true,
  visibleWhenKey: 'network',
  visibleWhenValue: 'ws',
  help: '旧版写法，建议改用 ws-opts.headers',
);

const FieldSpec _realityOptsField = FieldSpec(
  key: 'reality-opts',
  labelZh: 'REALITY 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  help: 'REALITY 伪装参数（公钥 / short-id）',
);

const FieldSpec _realityOptsFieldIfTls = FieldSpec(
  key: 'reality-opts',
  labelZh: 'REALITY 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'REALITY 伪装参数（公钥 / short-id）',
);

const FieldSpec _echOptsField = FieldSpec(
  key: 'ech-opts',
  labelZh: 'ECH 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  help: '加密客户端问候（ECH）参数',
);

const FieldSpec _echOptsFieldIfTls = FieldSpec(
  key: 'ech-opts',
  labelZh: 'ECH 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: '加密客户端问候（ECH）参数',
);

const FieldSpec _shadowTlsOptsField = FieldSpec(
  key: 'shadow-tls-opts',
  labelZh: 'ShadowTLS 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  help: 'ShadowTLS v3 伪装参数',
);

const FieldSpec _shadowTlsOptsFieldIfTls = FieldSpec(
  key: 'shadow-tls-opts',
  labelZh: 'ShadowTLS 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'ShadowTLS v3 伪装参数',
);

const FieldSpec _restlsOptsField = FieldSpec(
  key: 'restls-opts',
  labelZh: 'Restls 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  help: 'Restls 抗审查伪装参数',
);

const FieldSpec _restlsOptsFieldIfTls = FieldSpec(
  key: 'restls-opts',
  labelZh: 'Restls 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'Restls 抗审查伪装参数',
);

const FieldSpec _jlsOptsField = FieldSpec(
  key: 'jls-opts',
  labelZh: 'JLS 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  help: 'JLS 伪装参数',
);

const FieldSpec _jlsOptsFieldIfTls = FieldSpec(
  key: 'jls-opts',
  labelZh: 'JLS 设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'JLS 伪装参数',
);

// ---------------------------------------------------------------------------
// 无条件的自由 Map 字段
// ---------------------------------------------------------------------------

const FieldSpec _pluginOptsField = FieldSpec(
  key: 'plugin-opts',
  labelZh: '插件参数',
  kind: FieldKind.map,
  group: FieldGroup.protocol,
  advanced: true,
  help: '随插件选择填写，如 mode / host / tls',
);

const FieldSpec _realmOptsField = FieldSpec(
  key: 'realm-opts',
  labelZh: 'Realm 设置',
  kind: FieldKind.map,
  group: FieldGroup.advanced,
  advanced: true,
  help: 'Realm 穿透参数，如 enable / server-url / token',
);

const FieldSpec _amneziaWgOptionField = FieldSpec(
  key: 'amnezia-wg-option',
  labelZh: 'AmneziaWG 参数',
  kind: FieldKind.map,
  group: FieldGroup.advanced,
  advanced: true,
  help: 'AmneziaWG 混淆参数，键值对',
);

const FieldSpec _mekyaOptsField = FieldSpec(
  key: 'mekya-opts',
  labelZh: 'Mekya 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  advanced: true,
  help: 'Mekya 传输参数，键值对',
);

const FieldSpec _mkcpOptsField = FieldSpec(
  key: 'mkcp-opts',
  labelZh: 'MKCP 设置',
  kind: FieldKind.map,
  group: FieldGroup.transport,
  advanced: true,
  help: 'MKCP 传输参数，键值对',
);

const FieldSpec _tlsMirrorOptsField = FieldSpec(
  key: 'tlsmirror-opts',
  labelZh: 'TLS 镜像设置',
  kind: FieldKind.map,
  group: FieldGroup.tls,
  advanced: true,
  visibleWhenKey: 'tls',
  visibleWhenValue: true,
  help: 'TLS 镜像实验参数，键值对',
);

const FieldSpec _httpHeadersField = FieldSpec(
  key: 'headers',
  labelZh: '请求头',
  kind: FieldKind.map,
  group: FieldGroup.protocol,
  help: '附加 HTTP 请求头，键值对',
);

// ---------------------------------------------------------------------------
// 嵌套结构（MapSchema）
// ---------------------------------------------------------------------------

const MapSchema _wsOpts = MapSchema(
  key: 'ws-opts',
  labelZh: 'WebSocket 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'path',
      labelZh: '路径',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      help: 'WebSocket 握手路径，如 /ws',
    ),
    FieldSpec(
      key: 'headers',
      labelZh: '请求头',
      kind: FieldKind.map,
      group: FieldGroup.transport,
      help: '附加请求头，键值对',
    ),
    FieldSpec(
      key: 'max-early-data',
      labelZh: '最大早期数据',
      kind: FieldKind.int,
      group: FieldGroup.transport,
      advanced: true,
      help: '0-RTT 最大字节数，0 表示关闭',
    ),
    FieldSpec(
      key: 'early-data-header-name',
      labelZh: '早期数据头名',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      advanced: true,
      help: '通常为 Sec-WebSocket-Protocol',
    ),
    FieldSpec(
      key: 'v2ray-http-upgrade',
      labelZh: 'V2Ray HTTP Upgrade',
      kind: FieldKind.bool,
      group: FieldGroup.transport,
      advanced: true,
      help: '用 HTTP Upgrade 代替 WebSocket 握手',
    ),
    FieldSpec(
      key: 'v2ray-http-upgrade-fast-open',
      labelZh: 'Upgrade 快速打开',
      kind: FieldKind.bool,
      group: FieldGroup.transport,
      advanced: true,
      help: '复用连接时跳过 Upgrade 握手',
    ),
  ],
);

const MapSchema _grpcOpts = MapSchema(
  key: 'grpc-opts',
  labelZh: 'gRPC 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'grpc-service-name',
      labelZh: 'gRPC 服务名',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      help: '与服务端 serviceName 一致',
    ),
    FieldSpec(
      key: 'grpc-user-agent',
      labelZh: 'gRPC User-Agent',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      advanced: true,
      help: '自定义 User-Agent',
    ),
    FieldSpec(
      key: 'ping-interval',
      labelZh: '心跳间隔',
      kind: FieldKind.int,
      group: FieldGroup.transport,
      advanced: true,
      help: '单位：秒',
    ),
    FieldSpec(
      key: 'max-connections',
      labelZh: '最大连接数',
      kind: FieldKind.int,
      group: FieldGroup.transport,
      advanced: true,
      help: '留空由内核决定',
    ),
    FieldSpec(
      key: 'min-streams',
      labelZh: '最小流数',
      kind: FieldKind.int,
      group: FieldGroup.transport,
      advanced: true,
      help: '留空由内核决定',
    ),
    FieldSpec(
      key: 'max-streams',
      labelZh: '最大流数',
      kind: FieldKind.int,
      group: FieldGroup.transport,
      advanced: true,
      help: '留空由内核决定',
    ),
  ],
);

const MapSchema _h2Opts = MapSchema(
  key: 'h2-opts',
  labelZh: 'HTTP/2 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'host',
      labelZh: '主机名',
      kind: FieldKind.stringList,
      group: FieldGroup.transport,
      help: 'HTTP/2 的 Host，可填多个',
    ),
    FieldSpec(
      key: 'path',
      labelZh: '路径',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      help: 'HTTP/2 伪装路径',
    ),
  ],
);

const MapSchema _httpOpts = MapSchema(
  key: 'http-opts',
  labelZh: 'HTTP 伪装设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'method',
      labelZh: '请求方法',
      kind: FieldKind.enumChoice,
      group: FieldGroup.transport,
      options: <String>['GET', 'POST', 'HEAD'],
      defaultValue: 'GET',
      help: 'HTTP 伪装使用的请求方法',
    ),
    FieldSpec(
      key: 'path',
      labelZh: '路径',
      kind: FieldKind.stringList,
      group: FieldGroup.transport,
      help: '可填多个伪装路径',
    ),
    FieldSpec(
      key: 'headers',
      labelZh: '请求头',
      kind: FieldKind.map,
      group: FieldGroup.transport,
      help: '附加请求头，值可为列表',
    ),
  ],
);

const MapSchema _xhttpOpts = MapSchema(
  key: 'xhttp-opts',
  labelZh: 'XHTTP 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'host',
      labelZh: '主机名',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      help: 'Host 头，留空使用 server',
    ),
    FieldSpec(
      key: 'path',
      labelZh: '路径',
      kind: FieldKind.string,
      group: FieldGroup.transport,
      help: '请求路径',
    ),
    FieldSpec(
      key: 'mode',
      labelZh: '模式',
      kind: FieldKind.enumChoice,
      group: FieldGroup.transport,
      options: <String>['auto', 'packet-up', 'stream-up', 'stream-one'],
      defaultValue: 'auto',
      help: 'XHTTP 传输模式',
    ),
    FieldSpec(
      key: 'extra',
      labelZh: '额外参数',
      kind: FieldKind.map,
      group: FieldGroup.transport,
      advanced: true,
      help: '额外传输参数，键值对',
    ),
  ],
);

const MapSchema _realityOpts = MapSchema(
  key: 'reality-opts',
  labelZh: 'REALITY 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'public-key',
      labelZh: '公钥',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      required: true,
      help: '服务端 REALITY 公钥',
    ),
    FieldSpec(
      key: 'short-id',
      labelZh: '短 ID',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      help: '与服务端一致，可留空',
    ),
  ],
);

const MapSchema _echOpts = MapSchema(
  key: 'ech-opts',
  labelZh: 'ECH 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'enable',
      labelZh: '启用',
      kind: FieldKind.bool,
      group: FieldGroup.tls,
      help: '开启加密客户端问候',
    ),
    FieldSpec(
      key: 'config',
      labelZh: 'ECH 配置',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      help: 'ECHConfigList（Base64 字符串）',
    ),
  ],
);

const MapSchema _shadowTlsOpts = MapSchema(
  key: 'shadow-tls-opts',
  labelZh: 'ShadowTLS 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'version',
      labelZh: '版本',
      kind: FieldKind.int,
      group: FieldGroup.tls,
      defaultValue: 3,
      help: 'ShadowTLS 版本，通常填 3',
    ),
    FieldSpec(
      key: 'password',
      labelZh: '密码',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      secret: true,
      help: 'ShadowTLS 密码',
    ),
  ],
);

const MapSchema _restlsOpts = MapSchema(
  key: 'restls-opts',
  labelZh: 'Restls 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'version',
      labelZh: '版本',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      help: 'Restls 版本，如 1.4.2',
    ),
    FieldSpec(
      key: 'password',
      labelZh: '密码',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      secret: true,
      help: 'Restls 密码',
    ),
    FieldSpec(
      key: 'restls-script',
      labelZh: 'Restls 脚本',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      advanced: true,
      help: '留空使用默认脚本',
    ),
  ],
);

const MapSchema _jlsOpts = MapSchema(
  key: 'jls-opts',
  labelZh: 'JLS 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'version',
      labelZh: '版本',
      kind: FieldKind.int,
      group: FieldGroup.tls,
      help: 'JLS 协议版本',
    ),
    FieldSpec(
      key: 'password',
      labelZh: '密码',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      secret: true,
      help: 'JLS 密码',
    ),
    FieldSpec(
      key: 'full-client-random',
      labelZh: '完全随机客户端',
      kind: FieldKind.string,
      group: FieldGroup.tls,
      advanced: true,
      help: '指定完全随机的客户端特征，可留空',
    ),
  ],
);

const MapSchema _ssOpts = MapSchema(
  key: 'ss-opts',
  labelZh: 'Shadowsocks 设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'enabled',
      labelZh: '启用',
      kind: FieldKind.bool,
      group: FieldGroup.protocol,
      help: '启用 Shadowsocks 双层加密',
    ),
    FieldSpec(
      key: 'method',
      labelZh: '加密方式',
      kind: FieldKind.string,
      group: FieldGroup.protocol,
      help: 'Shadowsocks 加密方式',
    ),
  ],
);

const MapSchema _obfsOpts = MapSchema(
  key: 'obfs-opts',
  labelZh: '混淆设置',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'mode',
      labelZh: '混淆模式',
      kind: FieldKind.enumChoice,
      group: FieldGroup.protocol,
      options: <String>['http', 'tls'],
      defaultValue: 'http',
      help: 'Snell 混淆方式',
    ),
    FieldSpec(
      key: 'host',
      labelZh: '混淆主机名',
      kind: FieldKind.string,
      group: FieldGroup.protocol,
      help: '混淆使用的 Host',
    ),
  ],
);

const MapSchema _peers = MapSchema(
  key: 'peers',
  labelZh: 'WireGuard 对端',
  fields: <FieldSpec>[
    FieldSpec(
      key: 'server',
      labelZh: '服务器',
      kind: FieldKind.string,
      group: FieldGroup.protocol,
      required: true,
      help: '对端域名或 IP',
    ),
    FieldSpec(
      key: 'port',
      labelZh: '端口',
      kind: FieldKind.int,
      group: FieldGroup.protocol,
      required: true,
      help: '对端端口，通常 51820',
    ),
    FieldSpec(
      key: 'public-key',
      labelZh: '公钥',
      kind: FieldKind.string,
      group: FieldGroup.protocol,
      required: true,
      help: '对端 WireGuard 公钥',
    ),
    FieldSpec(
      key: 'pre-shared-key',
      labelZh: '预共享密钥',
      kind: FieldKind.string,
      group: FieldGroup.protocol,
      secret: true,
      help: '可选的预共享密钥',
    ),
    FieldSpec(
      key: 'reserved',
      labelZh: 'RESERVED',
      kind: FieldKind.stringList,
      group: FieldGroup.protocol,
      advanced: true,
      help: '三个整数，如 0,0,0',
    ),
    FieldSpec(
      key: 'allowed-ips',
      labelZh: '允许的 IP',
      kind: FieldKind.stringList,
      group: FieldGroup.protocol,
      help: '如 0.0.0.0/0, ::/0',
    ),
  ],
);

// ---------------------------------------------------------------------------
// 各协议 schema
// ---------------------------------------------------------------------------

const FieldSpec _typeVless = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'vless',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeVmess = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'vmess',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeTrojan = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'trojan',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeSs = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'ss',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeHysteria2 = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'hysteria2',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeTuic = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'tuic',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeWireguard = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'wireguard',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeSocks5 = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'socks5',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeHttp = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'http',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeSnell = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'snell',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeSsh = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'ssh',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeAnytls = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'anytls',
  required: true,
  help: '节点协议类型',
);

const FieldSpec _typeSsr = FieldSpec(
  key: 'type',
  labelZh: '类型',
  kind: FieldKind.enumChoice,
  group: FieldGroup.basic,
  options: kSupportedProxyTypes,
  defaultValue: 'ssr',
  required: true,
  help: '节点协议类型',
);

// --- VLESS -----------------------------------------------------------------

const List<FieldSpec> _vlessFields = <FieldSpec>[
  _name,
  _typeVless,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'uuid',
    labelZh: 'UUID',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    help: '服务端用户 ID',
  ),
  FieldSpec(
    key: 'flow',
    labelZh: '流控方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['', 'xtls-rprx-vision'],
    defaultValue: '',
    help: '留空为普通 TLS；Vision 需服务端支持',
  ),
  FieldSpec(
    key: 'encryption',
    labelZh: '加密方式',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    defaultValue: 'none',
    help: 'VLESS 通常填 none',
  ),
  FieldSpec(
    key: 'network',
    labelZh: '传输方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.transport,
    options: _vlessNetworkOptions,
    defaultValue: 'tcp',
    help: '需与服务端一致',
  ),
  _tls,
  _alpnIfTls,
  _servernameIfTls,
  _skipCertIfTls,
  _nameCertIfTls,
  _fingerprintIfTls,
  _certificateIfTls,
  _privateKeyTlsIfTls,
  _clientFingerprintIfTls,
  _realityOptsFieldIfTls,
  _echOptsFieldIfTls,
  _shadowTlsOptsFieldIfTls,
  _restlsOptsFieldIfTls,
  _jlsOptsFieldIfTls,
  FieldSpec(
    key: 'packet-addr',
    labelZh: '包地址',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    advanced: true,
    help: 'UDP over TCP 的转发地址，一般留空',
  ),
  FieldSpec(
    key: 'xudp',
    labelZh: 'XUDP',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '启用 XUDP 全锥形 NAT',
  ),
  FieldSpec(
    key: 'packet-encoding',
    labelZh: '包编码',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['xudp', 'packetaddr', 'none'],
    defaultValue: 'none',
    advanced: true,
    help: 'UDP 包编码方式',
  ),
  _httpOptsField,
  _h2OptsField,
  _grpcOptsField,
  _wsOptsField,
  _xhttpOptsField,
  _wsHeadersField,
  ..._commonTail,
];

const List<MapSchema> _vlessNested = <MapSchema>[
  _wsOpts,
  _grpcOpts,
  _h2Opts,
  _httpOpts,
  _xhttpOpts,
  _realityOpts,
  _echOpts,
  _shadowTlsOpts,
  _restlsOpts,
  _jlsOpts,
];

const ProxySchema _vlessSchema = ProxySchema(
  type: 'vless',
  labelZh: 'VLESS',
  fields: _vlessFields,
  nested: _vlessNested,
);

// --- VMess -----------------------------------------------------------------

const List<String> _vmessCipherOptions = <String>[
  'auto',
  'aes-128-gcm',
  'chacha20-poly1305',
  'none',
  'zero',
];

const List<FieldSpec> _vmessFields = <FieldSpec>[
  _name,
  _typeVmess,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'uuid',
    labelZh: 'UUID',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    help: '服务端用户 ID',
  ),
  FieldSpec(
    key: 'alterId',
    labelZh: 'Alter ID',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    defaultValue: 0,
    help: 'VMess 旧版兼容字段，现代服务端填 0',
  ),
  FieldSpec(
    key: 'cipher',
    labelZh: '加密方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: _vmessCipherOptions,
    defaultValue: 'auto',
    help: '通常保持 auto',
  ),
  FieldSpec(
    key: 'network',
    labelZh: '传输方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.transport,
    options: _networkOptions,
    defaultValue: 'tcp',
    help: '需与服务端一致',
  ),
  _tls,
  _alpnIfTls,
  _skipCertIfTls,
  _nameCertIfTls,
  _fingerprintIfTls,
  _certificateIfTls,
  _privateKeyTlsIfTls,
  _servernameIfTls,
  _clientFingerprintIfTls,
  _echOptsFieldIfTls,
  _shadowTlsOptsFieldIfTls,
  _restlsOptsFieldIfTls,
  _jlsOptsFieldIfTls,
  _realityOptsFieldIfTls,
  _tlsMirrorOptsField,
  _mekyaOptsField,
  _mkcpOptsField,
  _httpOptsField,
  _h2OptsField,
  _grpcOptsField,
  _wsOptsField,
  FieldSpec(
    key: 'packet-addr',
    labelZh: '包地址',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    advanced: true,
    help: 'UDP over TCP 的转发地址，一般留空',
  ),
  FieldSpec(
    key: 'xudp',
    labelZh: 'XUDP',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '启用 XUDP 全锥形 NAT',
  ),
  FieldSpec(
    key: 'packet-encoding',
    labelZh: '包编码',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['xudp', 'packetaddr', 'none'],
    defaultValue: 'none',
    advanced: true,
    help: 'UDP 包编码方式',
  ),
  FieldSpec(
    key: 'global-padding',
    labelZh: '全局填充',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '对 VMess 流量做全局填充',
  ),
  FieldSpec(
    key: 'authenticated-length',
    labelZh: '认证长度',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '启用认证长度混淆',
  ),
  ..._commonTail,
];

const List<MapSchema> _vmessNested = <MapSchema>[
  _wsOpts,
  _grpcOpts,
  _h2Opts,
  _httpOpts,
  _realityOpts,
  _echOpts,
  _shadowTlsOpts,
  _restlsOpts,
  _jlsOpts,
];

const ProxySchema _vmessSchema = ProxySchema(
  type: 'vmess',
  labelZh: 'VMess',
  fields: _vmessFields,
  nested: _vmessNested,
);

// --- Trojan ----------------------------------------------------------------

const List<FieldSpec> _trojanFields = <FieldSpec>[
  _name,
  _typeTrojan,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'Trojan 服务端密码',
  ),
  _alpn,
  _sni,
  _skipCert,
  _nameCert,
  _fingerprint,
  _certificate,
  _privateKeyTls,
  FieldSpec(
    key: 'network',
    labelZh: '传输方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.transport,
    options: <String>['tcp', 'ws', 'grpc'],
    defaultValue: 'tcp',
    help: '需与服务端一致',
  ),
  _grpcOptsField,
  _wsOptsField,
  FieldSpec(
    key: 'ss-opts',
    labelZh: 'Shadowsocks 设置',
    kind: FieldKind.map,
    group: FieldGroup.protocol,
    help: 'Trojan 的 Shadowsocks 双层加密参数',
  ),
  _echOptsField,
  _shadowTlsOptsField,
  _restlsOptsField,
  _jlsOptsField,
  _realityOptsField,
  _clientFingerprint,
  ..._commonTail,
];

const List<MapSchema> _trojanNested = <MapSchema>[
  _wsOpts,
  _grpcOpts,
  _ssOpts,
  _echOpts,
  _shadowTlsOpts,
  _restlsOpts,
  _jlsOpts,
  _realityOpts,
];

const ProxySchema _trojanSchema = ProxySchema(
  type: 'trojan',
  labelZh: 'Trojan',
  fields: _trojanFields,
  nested: _trojanNested,
);

// --- Shadowsocks -----------------------------------------------------------

const List<String> _ssCipherOptions = <String>[
  'aes-128-gcm',
  'aes-192-gcm',
  'aes-256-gcm',
  'aes-128-cfb',
  'aes-192-cfb',
  'aes-256-cfb',
  'aes-128-ctr',
  'aes-192-ctr',
  'aes-256-ctr',
  'rc4-md5',
  'chacha20-ietf',
  'xchacha20',
  'chacha20-ietf-poly1305',
  'xchacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
];

const List<String> _ssPluginOptions = <String>[
  '',
  'obfs',
  'v2ray-plugin',
  'shadow-tls',
  'restls',
];

const List<FieldSpec> _ssFields = <FieldSpec>[
  _name,
  _typeSs,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'Shadowsocks 密码',
  ),
  FieldSpec(
    key: 'cipher',
    labelZh: '加密方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: _ssCipherOptions,
    defaultValue: 'aes-256-gcm',
    help: '需与服务端一致',
  ),
  FieldSpec(
    key: 'plugin',
    labelZh: '插件',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: _ssPluginOptions,
    defaultValue: '',
    help: '留空表示不使用插件',
  ),
  _pluginOptsField,
  FieldSpec(
    key: 'udp-over-tcp',
    labelZh: 'UDP over TCP',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '通过 TCP 转发 UDP',
  ),
  FieldSpec(
    key: 'udp-over-tcp-version',
    labelZh: 'UDP over TCP 版本',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    advanced: true,
    help: '通常留空使用默认版本',
  ),
  _clientFingerprint,
  ..._commonTail,
];

const List<MapSchema> _ssNested = <MapSchema>[];

const ProxySchema _ssSchema = ProxySchema(
  type: 'ss',
  labelZh: 'Shadowsocks',
  fields: _ssFields,
  nested: _ssNested,
);

// --- Hysteria2 -------------------------------------------------------------

const List<FieldSpec> _hysteria2Fields = <FieldSpec>[
  _name,
  _typeHysteria2,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'ports',
    labelZh: '端口跳跃',
    kind: FieldKind.portRange,
    group: FieldGroup.basic,
    help: '如 1000-2000 或 1000,2000-3000；设置后覆盖 port',
  ),
  FieldSpec(
    key: 'hop-interval',
    labelZh: '端口跳跃间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：秒',
  ),
  FieldSpec(
    key: 'up',
    labelZh: '上行带宽',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '如 30 Mbps，留空由内核探测',
  ),
  FieldSpec(
    key: 'down',
    labelZh: '下行带宽',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '如 100 Mbps，留空由内核探测',
  ),
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'Hysteria2 认证密码',
  ),
  FieldSpec(
    key: 'obfs',
    labelZh: '混淆方式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['', 'salamander'],
    defaultValue: '',
    help: '留空表示不混淆',
  ),
  FieldSpec(
    key: 'obfs-password',
    labelZh: '混淆密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '混淆开启时必填',
  ),
  FieldSpec(
    key: 'obfs-min-packet-size',
    labelZh: '混淆包大小下限',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    advanced: true,
    help: '单位：字节',
  ),
  FieldSpec(
    key: 'obfs-max-packet-size',
    labelZh: '混淆包大小上限',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    advanced: true,
    help: '单位：字节',
  ),
  _sni,
  _alpn,
  _skipCert,
  _nameCert,
  _fingerprint,
  _certificate,
  _privateKeyTls,
  _echOptsField,
  FieldSpec(
    key: 'cwnd',
    labelZh: '拥塞窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '留空由内核决定',
  ),
  FieldSpec(
    key: 'bbr-profile',
    labelZh: 'BBR 配置',
    kind: FieldKind.enumChoice,
    group: FieldGroup.advanced,
    options: <String>['conservative', 'standard', 'aggressive'],
    defaultValue: 'standard',
    advanced: true,
    help: '拥塞控制的激进程度',
  ),
  FieldSpec(
    key: 'udp-mtu',
    labelZh: 'UDP MTU',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '默认 1200',
  ),
  FieldSpec(
    key: 'handshake-timeout',
    labelZh: '握手超时',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：秒',
  ),
  _realmOptsField,
  FieldSpec(
    key: 'initial-stream-receive-window',
    labelZh: '初始流接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节，留空由内核决定',
  ),
  FieldSpec(
    key: 'max-stream-receive-window',
    labelZh: '最大流接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节，留空由内核决定',
  ),
  FieldSpec(
    key: 'initial-connection-receive-window',
    labelZh: '初始连接接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节，留空由内核决定',
  ),
  FieldSpec(
    key: 'max-connection-receive-window',
    labelZh: '最大连接接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节，留空由内核决定',
  ),
  ..._commonTail,
];

const List<MapSchema> _hysteria2Nested = <MapSchema>[_echOpts];

const ProxySchema _hysteria2Schema = ProxySchema(
  type: 'hysteria2',
  labelZh: 'Hysteria2',
  fields: _hysteria2Fields,
  nested: _hysteria2Nested,
);

// --- TUIC ------------------------------------------------------------------

const List<FieldSpec> _tuicFields = <FieldSpec>[
  _name,
  _typeTuic,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'token',
    labelZh: '令牌',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '新版 TUIC 常用，与 uuid/password 二选一',
  ),
  FieldSpec(
    key: 'uuid',
    labelZh: 'UUID',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '使用 token 时可留空',
  ),
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '使用 token 时可留空',
  ),
  FieldSpec(
    key: 'ip',
    labelZh: '服务器 IP',
    kind: FieldKind.string,
    group: FieldGroup.basic,
    help: '直连 IP，跳过 DNS 解析',
  ),
  FieldSpec(
    key: 'heartbeat-interval',
    labelZh: '心跳间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.protocol,
    help: '单位：秒',
  ),
  _alpn,
  FieldSpec(
    key: 'reduce-rtt',
    labelZh: '减少 RTT',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '开启 0-RTT 快速重连',
  ),
  FieldSpec(
    key: 'request-timeout',
    labelZh: '请求超时',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：毫秒',
  ),
  FieldSpec(
    key: 'udp-relay-mode',
    labelZh: 'UDP 中继模式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['native', 'quic'],
    defaultValue: 'native',
    help: 'native 为原生 UDP，quic 走 QUIC 流',
  ),
  FieldSpec(
    key: 'congestion-controller',
    labelZh: '拥塞控制算法',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['cubic', 'new_reno', 'bbr'],
    help: '建议 bbr',
  ),
  FieldSpec(
    key: 'disable-sni',
    labelZh: '禁用 SNI',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: 'TLS 握手不发送 SNI',
  ),
  FieldSpec(
    key: 'max-udp-relay-packet-size',
    labelZh: '最大 UDP 中继包',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节',
  ),
  FieldSpec(
    key: 'fast-open',
    labelZh: 'TCP Fast Open',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '需要系统与服务端支持',
  ),
  FieldSpec(
    key: 'max-open-streams',
    labelZh: '最大并发流',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '留空由内核决定',
  ),
  FieldSpec(
    key: 'cwnd',
    labelZh: '拥塞窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '留空由内核决定',
  ),
  FieldSpec(
    key: 'bbr-profile',
    labelZh: 'BBR 配置',
    kind: FieldKind.enumChoice,
    group: FieldGroup.advanced,
    options: <String>['conservative', 'standard', 'aggressive'],
    advanced: true,
    help: '拥塞控制的激进程度',
  ),
  _skipCert,
  _nameCert,
  _fingerprint,
  _certificate,
  _privateKeyTls,
  FieldSpec(
    key: 'recv-window-conn',
    labelZh: '连接接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节',
  ),
  FieldSpec(
    key: 'recv-window',
    labelZh: '流接收窗口',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节',
  ),
  FieldSpec(
    key: 'disable-mtu-discovery',
    labelZh: '禁用 MTU 发现',
    kind: FieldKind.bool,
    group: FieldGroup.advanced,
    advanced: true,
    help: '关闭 QUIC 的 MTU 自动发现',
  ),
  FieldSpec(
    key: 'max-datagram-frame-size',
    labelZh: '最大数据报帧',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：字节',
  ),
  _sni,
  _echOptsField,
  FieldSpec(
    key: 'udp-over-stream',
    labelZh: 'UDP over Stream',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '通过流复用转发 UDP',
  ),
  FieldSpec(
    key: 'udp-over-stream-version',
    labelZh: 'UDP over Stream 版本',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    advanced: true,
    help: '通常留空使用默认版本',
  ),
  ..._commonTail,
];

const List<MapSchema> _tuicNested = <MapSchema>[_echOpts];

const ProxySchema _tuicSchema = ProxySchema(
  type: 'tuic',
  labelZh: 'TUIC',
  fields: _tuicFields,
  nested: _tuicNested,
);

// --- WireGuard -------------------------------------------------------------

const List<FieldSpec> _wireguardFields = <FieldSpec>[
  _name,
  _typeWireguard,
  _udp,
  FieldSpec(
    key: 'ip',
    labelZh: '接口地址',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '本地 IP，如 172.16.0.2/32',
  ),
  FieldSpec(
    key: 'ipv6',
    labelZh: '接口 IPv6',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '本地 IPv6，如 fd00::2/128',
  ),
  FieldSpec(
    key: 'private-key',
    labelZh: '私钥',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: '本机 WireGuard 私钥',
  ),
  FieldSpec(
    key: 'workers',
    labelZh: '工作线程数',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '留空由内核决定',
  ),
  FieldSpec(
    key: 'mtu',
    labelZh: 'MTU',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '一般 1420',
  ),
  FieldSpec(
    key: 'persistent-keepalive',
    labelZh: '保活间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：秒',
  ),
  FieldSpec(
    key: 'ip-stack',
    labelZh: 'IP 栈',
    kind: FieldKind.enumChoice,
    group: FieldGroup.advanced,
    options: <String>['auto', 'dual', 'gvisor', 'lwip', 'system'],
    defaultValue: 'auto',
    advanced: true,
    help: '内核网络栈实现',
  ),
  _amneziaWgOptionField,
  FieldSpec(
    key: 'peers',
    labelZh: '对端节点',
    kind: FieldKind.map,
    group: FieldGroup.protocol,
    help: '可添加多个 WireGuard 对端',
  ),
  FieldSpec(
    key: 'remote-dns-resolve',
    labelZh: '远程 DNS 解析',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    advanced: true,
    help: '由服务端解析域名',
  ),
  FieldSpec(
    key: 'dns',
    labelZh: 'DNS 服务器',
    kind: FieldKind.stringList,
    group: FieldGroup.protocol,
    advanced: true,
    help: '隧道内使用的 DNS，可填多个',
  ),
  FieldSpec(
    key: 'refresh-server-ip-interval',
    labelZh: '刷新服务器 IP 间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：秒',
  ),
  ..._commonTail,
];

const List<MapSchema> _wireguardNested = <MapSchema>[_peers];

const ProxySchema _wireguardSchema = ProxySchema(
  type: 'wireguard',
  labelZh: 'WireGuard',
  fields: _wireguardFields,
  nested: _wireguardNested,
);

// --- SOCKS5 ----------------------------------------------------------------

const List<FieldSpec> _socks5Fields = <FieldSpec>[
  _name,
  _typeSocks5,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'username',
    labelZh: '用户名',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '代理认证用户名，可留空',
  ),
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '代理认证密码，可留空',
  ),
  _tls,
  _skipCertIfTls,
  _nameCertIfTls,
  _fingerprintIfTls,
  _certificateIfTls,
  _privateKeyTlsIfTls,
  ..._commonTail,
];

const List<MapSchema> _socks5Nested = <MapSchema>[];

const ProxySchema _socks5Schema = ProxySchema(
  type: 'socks5',
  labelZh: 'SOCKS5',
  fields: _socks5Fields,
  nested: _socks5Nested,
);

// --- HTTP ------------------------------------------------------------------

const List<FieldSpec> _httpFields = <FieldSpec>[
  _name,
  _typeHttp,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'username',
    labelZh: '用户名',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '代理认证用户名，可留空',
  ),
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '代理认证密码，可留空',
  ),
  _tls,
  _sniIfTls,
  _skipCertIfTls,
  _nameCertIfTls,
  _fingerprintIfTls,
  _certificateIfTls,
  _privateKeyTlsIfTls,
  _httpHeadersField,
  ..._commonTail,
];

const List<MapSchema> _httpNested = <MapSchema>[];

const ProxySchema _httpSchema = ProxySchema(
  type: 'http',
  labelZh: 'HTTP',
  fields: _httpFields,
  nested: _httpNested,
);

// --- Snell -----------------------------------------------------------------

const List<FieldSpec> _snellFields = <FieldSpec>[
  _name,
  _typeSnell,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'psk',
    labelZh: '预共享密钥',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'Snell 服务端 psk',
  ),
  FieldSpec(
    key: 'userkey',
    labelZh: '用户密钥',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '可选，部分服务端需要',
  ),
  FieldSpec(
    key: 'version',
    labelZh: '版本',
    kind: FieldKind.int,
    group: FieldGroup.protocol,
    help: 'Snell 版本，4 支持 UDP',
  ),
  FieldSpec(
    key: 'reuse',
    labelZh: '连接复用',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '复用已建立的连接',
  ),
  FieldSpec(
    key: 'mode',
    labelZh: '模式',
    kind: FieldKind.enumChoice,
    group: FieldGroup.protocol,
    options: <String>['default', 'unshaped'],
    defaultValue: 'default',
    help: 'unshaped 关闭流量整形',
  ),
  FieldSpec(
    key: 'obfs-opts',
    labelZh: '混淆设置',
    kind: FieldKind.map,
    group: FieldGroup.protocol,
    help: 'Snell 混淆参数',
  ),
  _clientFingerprint,
  ..._commonTail,
];

const List<MapSchema> _snellNested = <MapSchema>[_obfsOpts];

const ProxySchema _snellSchema = ProxySchema(
  type: 'snell',
  labelZh: 'Snell',
  fields: _snellFields,
  nested: _snellNested,
);

// --- SSH -------------------------------------------------------------------

const List<FieldSpec> _sshFields = <FieldSpec>[
  _name,
  _typeSsh,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'username',
    labelZh: '用户名',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: 'SSH 登录用户名',
  ),
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: '与私钥二选一',
  ),
  FieldSpec(
    key: 'private-key',
    labelZh: 'SSH 私钥',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    help: 'PEM 格式私钥，与密码二选一',
  ),
  FieldSpec(
    key: 'private-key-passphrase',
    labelZh: '私钥口令',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    secret: true,
    advanced: true,
    help: '私钥有口令时填写',
  ),
  FieldSpec(
    key: 'host-key',
    labelZh: '主机公钥',
    kind: FieldKind.string,
    group: FieldGroup.advanced,
    advanced: true,
    help: '固定服务端主机公钥，可留空',
  ),
  FieldSpec(
    key: 'host-key-algorithms',
    labelZh: '主机密钥算法',
    kind: FieldKind.stringList,
    group: FieldGroup.advanced,
    advanced: true,
    help: '限制可接受的算法，可留空',
  ),
  ..._commonTail,
];

const List<MapSchema> _sshNested = <MapSchema>[];

const ProxySchema _sshSchema = ProxySchema(
  type: 'ssh',
  labelZh: 'SSH',
  fields: _sshFields,
  nested: _sshNested,
);

// --- AnyTLS ----------------------------------------------------------------

const List<FieldSpec> _anytlsFields = <FieldSpec>[
  _name,
  _typeAnytls,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'AnyTLS 认证密码',
  ),
  _alpn,
  _sni,
  _skipCert,
  _nameCert,
  _fingerprint,
  _certificate,
  _privateKeyTls,
  FieldSpec(
    key: 'idle-session-check-interval',
    labelZh: '空闲检查间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：秒',
  ),
  FieldSpec(
    key: 'idle-session-timeout',
    labelZh: '空闲会话超时',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.protocol,
    help: '单位：秒',
  ),
  FieldSpec(
    key: 'min-idle-session',
    labelZh: '最小空闲会话数',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '保持空闲连接的数量',
  ),
  FieldSpec(
    key: 'disable-reuse',
    labelZh: '禁用连接复用',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '每次请求都新建连接',
  ),
  ..._commonTail,
];

const List<MapSchema> _anytlsNested = <MapSchema>[];

const ProxySchema _anytlsSchema = ProxySchema(
  type: 'anytls',
  labelZh: 'AnyTLS',
  fields: _anytlsFields,
  nested: _anytlsNested,
);

// --- ShadowsocksR ----------------------------------------------------------

const List<FieldSpec> _ssrFields = <FieldSpec>[
  _name,
  _typeSsr,
  _server,
  _port,
  _udp,
  FieldSpec(
    key: 'password',
    labelZh: '密码',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    required: true,
    secret: true,
    help: 'ShadowsocksR 密码',
  ),
  FieldSpec(
    key: 'cipher',
    labelZh: '加密方式',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '与 Shadowsocks 相同的加密方式',
  ),
  FieldSpec(
    key: 'obfs',
    labelZh: '混淆方式',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '如 plain、http_simple、tls1.2_ticket_auth',
  ),
  FieldSpec(
    key: 'obfs-param',
    labelZh: '混淆参数',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '混淆方式对应的参数，可留空',
  ),
  FieldSpec(
    key: 'protocol',
    labelZh: '协议插件',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '如 origin、auth_sha1_v4',
  ),
  FieldSpec(
    key: 'protocol-param',
    labelZh: '协议参数',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '协议插件对应的参数，可留空',
  ),
  ..._commonTail,
];

const List<MapSchema> _ssrNested = <MapSchema>[];

const ProxySchema _ssrSchema = ProxySchema(
  type: 'ssr',
  labelZh: 'ShadowsocksR',
  fields: _ssrFields,
  nested: _ssrNested,
);

/// 全部节点类型 schema（顺序与 [kSupportedProxyTypes] 一致）。
const List<ProxySchema> kProxySchemas = <ProxySchema>[
  _vlessSchema,
  _vmessSchema,
  _trojanSchema,
  _ssSchema,
  _hysteria2Schema,
  _tuicSchema,
  _wireguardSchema,
  _socks5Schema,
  _httpSchema,
  _snellSchema,
  _sshSchema,
  _anytlsSchema,
  _ssrSchema,
];

/// 按 YAML 里的 `type` 查 schema；未知类型返回 `null`。
ProxySchema? proxySchemaFor(String type) {
  for (final schema in kProxySchemas) {
    if (schema.type == type) {
      return schema;
    }
  }
  return null;
}

/// 支持的节点类型列表（供下拉框使用）。
List<String> get supportedProxyTypes => kSupportedProxyTypes;

/// 一个节点类型的完整字段描述。
///
/// [fields] 里也包含嵌套块的入口字段（`kind: FieldKind.map`），
/// 用于条件显示；具体子字段定义在 [nested] 中，两者按 key 对应。
class ProxySchema {
  const ProxySchema({
    required this.type,
    required this.labelZh,
    required this.fields,
    required this.nested,
  });

  /// 与 YAML 里 `type` 的取值一致，例如 `vless`。
  final String type;

  /// 下拉框里显示的中文/协议名。
  final String labelZh;

  /// 顶层字段（顺序即表单顺序）。
  final List<FieldSpec> fields;

  /// 该类型支持的嵌套块。
  final List<MapSchema> nested;

  /// 按 key 找字段；找不到返回 `null`。
  FieldSpec? find(String key) {
    for (final spec in fields) {
      if (spec.key == key) {
        return spec;
      }
    }
    return null;
  }

  /// [find] 的别名，语义相同。
  FieldSpec? fieldByKey(String key) => find(key);

  /// 按 key 找嵌套块定义；找不到返回 `null`。
  MapSchema? nestedFor(String key) {
    for (final map in nested) {
      if (map.key == key) {
        return map;
      }
    }
    return null;
  }
}

/// 嵌套块的字段描述（`ws-opts` / `grpc-opts` / `reality-opts` 等）。
class MapSchema {
  const MapSchema({
    required this.key,
    required this.labelZh,
    required this.fields,
  });

  /// 与 YAML 键名一致，例如 `ws-opts`。
  final String key;

  /// 中文标签。
  final String labelZh;

  /// 嵌套块内部的字段。
  final List<FieldSpec> fields;

  /// 按 key 找子字段；找不到返回 `null`。
  FieldSpec? find(String fieldKey) {
    for (final spec in fields) {
      if (spec.key == fieldKey) {
        return spec;
      }
    }
    return null;
  }
}
