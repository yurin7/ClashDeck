# ClashDeck — 架构设计

> 一个面向 Android 的 mihomo（Clash.Meta）图形客户端：**直接以 YAML 配置为唯一真相源**，
> 提供可视化编辑（新增 vless 节点、节点跨组拖拽、规则组编辑）与内置内核运行。

工作名 `ClashDeck`（包名 `dev.clashdeck`），GPL-3.0。

---

## 1. 为什么不用内核 API 做增删改

mihomo 的 RESTful API（`external-controller`）只支持：

- `GET /proxies`、`PUT /proxies/:name`（仅切换选中项）、`GET /proxies/:name/delay`
- `GET /configs`、`PATCH /configs`（只有 port / mode / log-level 等少数字段）、
  `PUT /configs`（`{"path": "...", "payload": "yaml 文本"}` → 重新加载配置）
- `GET /rules` / `GET /providers/proxies` 等只读接口

即：**没有增删节点、增删分组、编辑规则的写接口**。所以编辑能力必须由 App 自己维护 YAML，
改完后用 `PUT /configs?force=true`（或 App 内直接重启内核）热加载。

由此得到本项目的核心难点：**无损回写（lossless rewrite）**——用户往往拿着一份带注释、
带大量内核私有字段的订阅配置，App 不能把它"洗"成自己认识的子集再吐回去。

## 2. 无损编辑策略（已用 spike 验证）

依赖 [`yaml_edit`](https://pub.dev/packages/yaml_edit) 2.2.4（dart-lang 官方，BSD-3）：
它在**原始源码文本**上做局部替换，未触及的区域（注释、空行、键顺序、未知字段）逐字保留。

`tool/spike_yaml.dart`、`tool/spike_yaml2.dart` 的实测结论：

| 场景 | 结果 |
| --- | --- |
| 向 `proxy-groups[i].proxies` 追加字符串 | `- HK-02`，块状，其余不动 |
| 向 `proxies` 追加一个 Map（节点） | **块状多行**输出，缩进正确，不会变成 `{...}` 行内风格 |
| 在已有节点下新增嵌套 Map（`ws-opts` / `reality-opts`） | 块状，缩进相对父键 +2 |
| 修改标量（改 `name`） | 仅替换该标量的 span；注释与其余字段不动；不必要的引号会被去掉 |
| 删除列表项 | 整行删除，相邻注释保留 |
| 含 `:`、`#`、CJK 的值 | 自动加引号：`name: "香港 01: 测试 #1"` |

**结论**：不需要自写 span 级文本手术；`yaml_edit` 足够。但要注意三个限制（都是实测坑）：

1. 它只有"整体替换某路径的值"这一种写操作 → 列表的增删/排序都要**算出完整新列表**再 `update`。
   因此所有编辑操作定义为：`(当前源码, 语义操作) -> 新源码`。
2. `YamlNode.span.end` 会包含节点后的空白/换行，**不能**用来做行级拼接（实测坑）。
3. 对**空 flow 列表**（如骨架配置里的 `proxies: []`）调 `appendToList` 会把整个列表改写成
   flow 一行 `proxies: [{name: ..., type: ...}]`；必须先 `update(path, [新项])` 展开成块状。
   `lib/core/edit/config_ops.dart` 已按"非空才 append/insert"实现。

## 3. 分层（实际布局）

```
lib/
  core/                     纯 Dart，可单元测试（无 Flutter 依赖）
    yaml/yaml_doc.dart      源码 + yaml_edit 封装；apply() 是唯一写入入口（失败无副作用）
    model/profile.dart      只读模型：Profile / ProxyEntry / GroupEntry / RuleEntry
    edit/config_ops.dart    编辑操作，全部 (YamlDoc, ...) -> YamlDoc，按名字定位
    schema/                 字段描述表（13 种协议 + 20 个组字段），驱动动态表单
    parse/share_link.dart   vless:// 等 10 种分享链接 + 整段 base64 订阅解析
    parse/subscription.dart 订阅 URL 拉取：明文 / base64 / 整份 YAML 三种订阅体 + subscription-userinfo
    edit/import_links.dart  把链接或订阅节点批量并入**已有**文档（重名去重、可选进组）
edit/import_rules.dart   导入规则行或整段 Clash 片段（rules + proxy-groups + providers 一起并，缺目标自动建组）
    validate/validator.dart 配置体检：重名、悬空引用、必填缺失、规则兜底等 30 类问题
  data/profile_store.dart   配置文件的落盘（tmp+rename 原子写）、骨架配置生成、订阅地址 sidecar meta
  state/editor_state.dart   ChangeNotifier：当前文档 + 撤销栈 + 脏标记 + 保存
  ui/                       theme.dart(暗色仪表盘令牌: Insets/Radiuses/display/mono/SemanticColors)
                          widgets.dart(AppCard/MicroLabel/Hairline/StatTile/StatusDot/AccentButton/Sparkline/Pill/MetaRow/EmptyHint)
                          app_shell.dart(三页悬浮岛: 概览/配置/设置, 唯一 RuntimeController + AppPrefs + SettingsState)
                          overview_page.dart / settings_page.dart / app_picker_page.dart(分应用名单)
                          home_page(配置列表) / editor_page(3 tab) / proxy_board 拖拽 / node_form_page
                          rules_tab / raw_yaml_tab / runtime_page / import_dialogs / rule_edit_dialog
state/                    editor_state(撤销/重做) + settings_state(读 YAML + sidecar meta, 所有开关的写入点)
data/                     profile_store(YAML + <名字>.yaml.meta.json) + app_prefs(app_prefs.json: 运行配置/上次订阅更新)
core/model/               profile / config_summary / app_settings(ProxyMode/AppRouteMode 等)
  runtime/                  mihomo 子进程编排：mihomo_api / runtime_config / runtime_controller
test/                       与 core 一一对应的单测 + widget 回归（239 个）
android/app/src/main/kotlin/dev/clashdeck/
  ClashVpnService.kt        VpnService：建 TUN → 把 fd 交给内核
  MihomoCore.kt             mihomo 子进程生命周期 + 日志环
  RuntimeBridge.kt          MethodChannel 双向桥（Dart 生成运行配置，Kotlin 回调状态）
  MainActivity.kt           start / stop / status / logs 方法实现 + VPN 授权流程
```

关键设计：**UI 不直接改文本**。UI 调 `ConfigOps` 里的操作拿到新 `YamlDoc`，经 `EditorState.apply()`
进撤销栈并刷新模型；保存才落盘。`EditorState.apply` 捕获 `ConfigEditException` 后置 `lastError`，
保证"失败无副作用"。


## 4. 数据模型要点

- `proxies` 是"节点池"，`proxy-groups[].proxies` 是**显式成员列表**，一个节点可属于多个组。
- 组如果带 `include-all` / `include-all-proxies` / `filter` / `exclude-filter`，成员是**运行时计算**的，
  此时 `proxies` 只影响显式部分 → UI 必须区分"显式成员"与"自动纳入"，拖拽要给出提示。
- 规则是字符串数组：`TYPE,PAYLOAD,TARGET[,no-resolve]`。拖动排序 = 重排数组。
- 改名要联动：节点名在 `proxies[i].name`、各组成员列表、规则目标、`dialer-proxy` 里出现。

## 5. 内核运行（子进程 + fd 继承，不用 FFI）

调研 `mihomo` 源码后确定的方案（关键证据）：

- `config/config.go` 的 `RawTun` 有 `file-descriptor`（`file-descriptor: 12` 这样的 YAML 键），
  `listener/sing_tun/server.go:152` 在 `FileDescriptor > 0` 时直接接管这个 fd，**不自己建设备**；
  `sing-tun@v0.4.29` 的 `tun_linux.go:51-71` 证明 fd 模式下它不做任何 netlink 地址/路由配置
  （地址由 `VpnService.Builder` 负责）。
- `listener/config/tun.go:222` 用 `FileDescriptor` 做相等性比较 → 热重载时只要 tun 段完全一致，
  这个 listener 会被**复用**，不会关掉我们的 fd。所以 `PUT /configs` 推整份运行配置是安全的。
- `RawTun` 里 **`inet4-address` 已被注释掉**（本版不读），运行配置里不要写它。
- `dns-hijack: [any:53]` 会把任意目的地址的 53 端口拦到内核内置 DNS，配 `dns.enhanced-mode: fake-ip`
  即可，不需要 `dns.listen`。

于是运行链路是：

```
VpnService.Builder.establish() -> ParcelFileDescriptor
  -> Os.fcntlInt(fd, F_SETFD, 0)   // 清 CLOEXEC，否则子进程拿不到
  -> detachFd() -> Int fd
  -> MethodChannel "buildRuntimeConfig" 让 Dart 生成运行配置（写入 tun.file-descriptor: fd）
  -> NativeSpawn.spawn(...)         // 自己 fork + execv（见下）
  -> 内核在 127.0.0.1:<port> 上开 external-controller，Dart 侧用 HTTP 查询状态/流量/测速
```

**必须自己 fork/exec，不能用 `ProcessBuilder`**（实测过）：

- Android 上 Java 的 `ProcessBuilder` 走 `posix_spawn` + `POSIX_SPAWN_CLOEXEC_DEFAULT`，
  会把父进程除 stdio 外的**所有 fd 关掉**，清 `FD_CLOEXEC` 也没用。日志表现为：
  `[TUN] get tun name failed for fd 162` +
  `Start TUN listening error: unix.SetNonblock(162) failed: bad file descriptor`。
- 改用 `android/app/src/main/cpp/spawn.c` 里的 JNI shim：`fork()` 后子进程只做
  `chdir` / `fcntl(tunFd, F_SETFD, flags & ~FD_CLOEXEC)` / 把 stdout+stderr 重定向到
  `core.log` / `execv`，失败 `_exit(127)`，全部 async-signal-safe。
  fork 出的子进程继承完整 fd 表，**fd 号父子一致**，所以 Dart 生成的
  `tun.file-descriptor` 不需要换算。
- 既然拿不到子进程的 stdout 管道，`MihomoCore` 改成**tail 日志文件**（`RandomAccessFile`
  增量读，`core.log`），这样内核启动期（REST 还没起来时）的报错也能看到。
- Kotlin `object` 里的 `external fun` 编成**实例方法**，所以 JNI 第二个参数是 `jobject thiz`，
  不是 `jclass`（写错会 `UnsatisfiedLinkError`）。

要点：

- mihomo 编译为 **linux/arm64 纯 Go 静态二进制**：`CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -tags with_gvisor`。
  （Go 的 `GOOS=android` 需要 cgo，而纯 Go 静态二进制在 Android 上同样能跑。）但 `GOOS=linux`
  会漏掉 android 专用代码，**必须打 §5.2 的 anet 补丁**。
- 产物放到 `android/app/src/main/jniLibs/arm64-v8a/libmihomo.so`，借 `nativeLibraryDir` 的
  **可执行权限**绕开 Android 10+ 对 `data_dir` 的 W^X 限制；因此 `AndroidManifest` 必须
  `android:extractNativeLibs="true"`（否则 AGP 把 .so 留在 APK 里不解压，`nativeLibraryDir` 是空的）。
- `packaging { jniLibs { keepDebugSymbols += "**/libmihomo.so" } }`：AGP 不能 strip 这个 Go 二进制。
- 修改配置后：`PUT /configs?force=true`，body `{"path":"","payload":"<整份运行配置>"}`。
  payload 里的 tun 段与启动时完全一致 → listener 复用，fd 不被关掉，代理不中断。

### 5.1 为什么要自带 GEOIP / GEOSITE 数据

`component/geodata/init.go` 里，内核在 `-d` 目录找不到数据时会**同步下载**：

- `InitGeoIP()`：非 `geodata-mode` 下找 `country.mmdb` / `geoip.db` / `geoip.metadb`
  （`constant/path.go` 的 `MMDB()` 按文件名匹配），找不到就 `Can't find MMDB, start download`
  → 下载默认 URL `https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb`；
- `InitGeoSite()`：找 `geosite.dat`，默认从同一个 release 下 `geosite.dat`。

实测（WSL，本机网络）这个下载 25 KB/s 左右、90 秒超时，于是**带 `GEOIP,CN,DIRECT` 这类规则的配置
直接 `configuration file ... test failed`**。手机上只会更差。

所以把 `geoip.metadb`(8.0 MB) 和 `geosite.dat`(4.2 MB) 打进 Flutter assets
（`assets/geo/`），`RuntimeController.start()` 在拉内核之前调用 `Geodata.ensure(workDir)`
把它们原子写入（`*.tmp` + rename，已存在且非空则跳过），然后内核就能离线解析 GEOIP/GEOSITE。

### 5.2 `GOOS=linux` 下必须补 anet 构建约束（否则 UDP/QUIC 全废）

第一次在 x86_64 模拟器跑通链路后，TCP 正常（延迟 87–148 ms），但日志里全是：

```
[UDP] dial PROXY ... error: route ip+net: netlinkrib: permission denied
```

原因：Android 上新版 SELinux 拒绝对 App 开放 `NETLINK_ROUTE` 的 route dump，Go 的
`net.Interfaces()` / `net.InterfaceAddrs()` 会失败。mihomo 早就带了修复——
`component/iface/anet/` 下有一份从 `wlynxg/anet` 移植的纯 Go netlink 实现
（`doc.go` 原话："Package anet fix \"route ip+net: netlinkrib: permission denied\" on android"），
但它的文件名是 `interface_android.go` / `netlink_android.go`，**只在 `GOOS=android` 时编译**。
我们为了免 cgo 用 `GOOS=linux`，于是这份修复被排除在外。

补丁（`tool/build_core.ps1` 已自动化，幂等）：

1. `interface_android.go` → `interface_anet.go`，构建约束改 `//go:build android || linux`；
2. `netlink_android.go` → `netlink_anet.go`，同样改；
3. `interface.go`（原本 `//go:build !android`，只有三行 `net.*` 直通）改
   `//go:build !android && !linux`，否则函数重名。

补丁后 `netlinkrib` 报错 0 条，UDP/QUIC 正常。

### 5.3 默认 DNS 用明文 UDP，不用 DoH

内核里的 DoH 走 Go 自己的 TLS 栈：模拟器上实测 `requesting https://223.5.5.5:443/dns-query`
报 `x509: certificate signed by unknown authority`（系统根证书在 Go 里匹配不到），
**DNS 一废整条链路就废**。所以骨架配置与 `RuntimeConfig` 的默认 nameserver 都是
`223.5.5.5` / `119.29.29.29`（UDP 53，由内核自己的 outbound 直连发出，最稳），
并补 `default-nameserver`。想用 DoH 的用户自己在 `dns:` 段里写——`_ensureDns` 只补缺、不覆盖。


### 5.4 配置保存后重启内核，而不是热重载

mihomo 的 `PUT /configs` 只重建 listener 与规则，**改不了 tun / dns-hijack / 代理模式**这类
启动参数；而用户保存配置时最常改的恰好是节点与规则目标。所以 0.3.4 起改成：

- 保存的是**当前运行配置**、且内核正处于 running/starting → 500ms 去抖后 `stop()` → `start(force: true)`；
- 保存其它配置只写盘，不打断正在运行的内核；
- 设置页改动、订阅更新（只针对当前配置）同样走重启。

`RuntimeController.restartIfRunning()` 负责去抖与串行（重启期间再保存会合并），
`shouldRestartAfterSave()` 是「是否该重启」的纯函数，便于单测。

## 6. 里程碑与现状

| 阶段 | 交付 | 状态 |
| --- | --- | --- |
| M1 | 配置读取 + 模型 + 编辑操作 + 体检 + 分享链接/订阅解析 + 单测 | ✅ 239 个测试全绿 |
| M2 | Flutter UI：配置列表、分组视图（跨组拖拽）、节点动态表单、规则编辑、YAML 视图 | ✅ 已实现，模拟器逐条走通（新增节点、组内移除/添加成员、新增规则落在 MATCH 之前、保存落盘） |
| M3 | 导入（粘贴链接/订阅/YAML）、另存为、原子保存 | ✅ 已实现 |
| M4 | 内核：mihomo 子进程 + VpnService 传 fd + 运行页（状态/流量/延迟/日志/热重载） | ✅ 模拟器（x86_64 / Android 16）跑通：TUN 监听成功、REST 在线、延迟 87–148 ms；待真机复验 |
| M5 | 打磨：订阅定时更新、应用分流、主题、图标、崩溃日志 | ⬜ 未开始 |

模拟器上只有两处"测不到"而非"不能用"的：长按拖拽没法用 `adb input` 合成手势可靠触发（每次
`input` 是独立进程，指针会话不连续），测试改走同一套 `ConfigOps` 的移除/添加成员路径；规则的
content-desc 在 uiautomator 里被截成 `1…`，屏幕上是完整的 `GEOIP / CN → DIRECT`。

## 7. 构建

```powershell
. D:\dev\env.ps1
cd E:\project\Agents\ClashAndroid
flutter test                    # 单测（Windows 上即可跑，无需设备）
flutter build apk --debug       # 打包 Debug APK
```

内核二进制的重新生成（仅在需要时）——**用脚本，别手敲**，它带 anet 补丁：

```powershell
. D:\dev\env.ps1
cd E:\project\Agents\ClashAndroid
./tool/build_core.ps1          # 源码默认取 D:\dev\_downloads\mihomo-src\mihomo-Alpha
# 换源码位置：./tool/build_core.ps1 -Source <mihomo 源码根目录>
```

脚本做的事：复制源码到 `D:\dev\_downloads\mihomo-patched`（不动原件）→ 打 §5.2 的 anet 补丁 →
`CGO_ENABLED=0 GOOS=linux GOARCH={arm64,amd64} go build -tags with_gvisor -trimpath -ldflags="-s -w"`
→ 直接写到 `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/libmihomo.so`。
**换内核后先 `flutter clean`**，否则 Gradle 可能复用旧产物。

真机验证步骤（`adb devices` 有设备时）：

```powershell
flutter run -d <device-id>
# App 内：新建配置 -> 导入 vless:// 链接 -> 编辑页右上"运行" -> 启动
adb logcat -s ClashDeck:I mihomo:V
```

