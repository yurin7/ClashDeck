# 更新日志

只记录技术改动；用户向说明见 [README](README.md)。格式参考 Keep a Changelog。

## [0.3.12] - 2026-11-25

### Fixed

- 链式代理批量加入按节点列表顺序追加，不再按面板里的点选顺序：新增 `orderNamesByNodeList`，先点 E 再点 D 追加出来仍是 D→E；节点列表里没有的名字保持相对顺序排在最后。

## [0.3.11] - 2026-11-24

### Fixed

- 链内拖拽补上过渡：拿起时浮层 120ms 放大到 1.04 并带阴影，原位保持 0.35 半透明占位。
- 间隙悬停时插入线 120ms 淡入并轻微放大，间隙宽度仍用 6↔28 的 `AnimatedContainer`。
- 松手换位后 `AnimatedSwitcher` 用 200ms 淡入 + 轻微推入呈现新顺序；`MediaQuery.disableAnimations` 为真时跳过全部过渡。

## [0.3.10] - 2026-11-23

### Fixed

- 链式代理新增成员固定追加到链尾：`addGroupMember` 不再按 `proxies` 定义顺序重排 relay 成员，A/B/C 删 A 再加回得到 B/C/A。
- 链内胶囊支持长按拖拽换位：`RelayMemberDragData` + 间隙目标接受链内成员，悬停显示插入线，落点按 gap 索引交给 `moveGroupMember`；⋮ 菜单的前移/后移保留。
- 节点选择器左下角按钮改名「添加节点」，并打开与节点列表右上「+」相同的三选一入口（手动填写 / 粘贴分享链接 / 从订阅链接导入），不再直接进手动表单。
## [0.3.9] - 2026-11-22

### Fixed

- 「本组规则」胶囊现在也能拖到系统策略卡（DIRECT / REJECT）：系统策略卡本身就是拖放目标，悬停高亮、松手后规则改挂到该策略并出现在它的「本组规则」里；卡片本身仍只读，不支持改名/删除/加节点。
## [0.3.8] - 2026-11-22

### Fixed

- 404 红条根因：重放设置里的组出口前先核对内核组与成员，失效条目直接从 sidecar 删除；重放失败不再把内核状态标成 error，内核在跑时自动清掉上一次操作错误。
- 链式代理真正能起内核：运行时配置把 `type: relay` 展开成 `dialer-proxy` 链（隐藏 `__chain_<组>_N` 代理，原组名改为只放末级的 `select`），用户配置文件保持原样，冷启动模板同样包含展开结果。
- 诊断与内核日志的计数改为与渲染列表同源（超过 120 行时显示「最近 N 行 / 共 M 行」）。

### Added

- 组卡外框状态：空组、链式成员不足、成员不存在、组名重复标红；成员全是直连/拒绝等可跑但可疑的情况标黄，优先级高于「当前出口」的紫色提示。
- 链式卡片不接受整卡拖入：同组拖动显示禁止标记并回弹，链内重排只通过胶囊之间的插入线完成。
## [0.3.7] - 2026-11-21

### Fixed

- 链式代理横向链条改为换行布局：长节点名省略号截断，序号徽标、箭头与「＋加一阶」不再被挤出屏幕。
- 遮罩手势与底层翻页彻底隔离：`PageView` 永久禁用滚动，抽屉打开/回收期间不会再误切到配置页或设置页。

## [0.3.6] - 2026-11-20

### Added

- 链式代理组支持横向链条编辑：按阶展示节点与箭头，首尾/间隙可拖入节点，胶囊菜单支持编辑、前移、后移、移出。
- 策略组支持自由拖拽：节点可跨组拖入、链内重排，合法落点显示紫色插入线。
- 自动组高亮：`url-test` 取当前最低延迟成员并标注「最低延迟」，`fallback` 优先最低延迟，`load-balance` 显示「自动均衡 · N 节点」。
- 非法拖拽（重复节点、落空白）后胶囊「滑回原位」240ms 回弹，重复悬停显示红框、🚫 角标与落点提示。
- Pulse 测速线路行换行展示；测速完成/失败文案统一为「测速会临时用独立内核，不影响当前配置」。

### Changed

- 概览页移除右上角刷新按钮，刷新统一走下拉/重进配置。
- 自定义测速地址栏出现/消失增加 200ms 过渡，去掉与输入框重复的错误文案。
- 遮罩半开时吞掉底页滚动，负向拖动只回收抽屉，`ScrollEnd` 使用真实速度判断开合。

### Fixed

- Pulse 抽屉滑出时正向拖动不再停在刚露头的位置，越过阈值后继续跟手。
- 链式代理链尾「加一阶」加大点击区，避免贴着横向滚动边缘点不中。
- 链式代理的节点选择面板只保留「节点」段，不再显示无法加入的系统策略与策略组。

### Tests

- 新增 `drag_state`、`drag_snapback`、`pulse_back_drag`、`group_status`、`relay_chain`、链式组加一阶与 picker 过滤测试；全量 715 tests。

## [0.3.5] - 2026-11-20

### Added

- 节点下载测速（Pulse 单节点）：测速源 Fast / Google / GitHub / 自定义，结果显示速度、大小与耗时；支持取消与失败重测。
- 内核无关的 TCP 延迟探针：内核未运行时也能测延迟，结果显示 `≈`；内核运行时仍走 mihomo 的 delay 接口。

### Changed

- 测速不再依赖节点出现在策略组：临时生成一份只含目标节点与 `speed-probe` 组的独立配置，测完即停临时内核，并按原状态恢复；不会改动用户配置。
- Pulse 遮罩的翻页锁改为「拖拽中不禁、打开后禁」，抽屉滑出过程不再被中途结算。

### Fixed

- 修复 Pulse 抽屉滑出时被打断：只出现细条、随后手势无响应，现在可完整拉出并在松手后正确结算。
- 修复跳板组识别：`type: select` 且成员写在 `proxies` 的真实配置不再误报「节点不在任何可选组」。
- 自动补测按配置名去重，切换配置后会重新补测一次；时间戳固定 24 小时制。
- 修复停止内核后概览仍显示旧 PID、下载速率不归零、内核日志保留上一次内容的问题。
- 去掉 Pulse 猫图标每 6 秒一次的自动纵向压扁（表现为「闪一下」）。

### Tests

- 测速最小配置生成、控制器临时内核序列（停旧 → 临时 → 恢复）、下载器中文错误文案、Pulse 手势守卫与物理选择。
- `test/speed_test_config_test.dart`、`test/speed_test_controller_flow_test.dart`、`test/pulse_entry_test.dart` 等。

## [0.3.4] - 2026-11-19

### Added

- Android 无界面启停入口：`ClashActionActivity` 可从通知、快捷磁贴或外部快捷方式直接启停内核；启动时写入 `runtime.yaml.tpl` 与 `RuntimePrefs` 快照，冷启动不必先打开 App。
- 常驻通知显示当前配置与全局出口，并提供「停止」动作；Android 13+ 首次启动会申请通知权限，设置页可查看状态并跳系统设置。
- 快捷设置磁贴：在 QS 面板直接启停内核，副标题显示当前配置。
- 2×1 桌面小组件：运行状态点、配置与全局出口一目了然，圆形按钮一键启停。
- 内核启动成功后自动测速一轮（每次启动只测一次，失败静默）；节点行与策略组成员芯片用延迟胶囊显示结果，节点列表区头新增「测速全部」，每个策略组卡新增「测本组」，手动测速保留。
- 规则列表信息层级重构：4dp 目标色条（DIRECT 绿 / REJECT 红 / 策略组紫）、标题只放中文名、类型标签移到行尾、目标 chip 放到第二行，点行查看完整详情。

### Changed

- 保存**当前运行配置**后自动重启内核，让节点/规则/启动参数一次生效；保存其它配置只写盘，不打断正在运行的内核。500ms 内连续保存合并为一次重启；设置页与订阅更新同样走重启而不是热重载。
- 运行态切换「运行模式」或「分流模式」后自动重启内核，统一由重启让改动生效。
- TUN 模式不再强制开启 DNS，可在设置里自由关闭（关闭时提醒「TUN 内域名可能无法解析」）；运行配置不再覆盖用户写的 `dns.enable`。
- Pulse 最终形态：概览页任意位置右滑拉出左侧 80% 遮罩，点暗区或左滑面板收起；去掉右缘手柄与左缘手势带，屏幕中部横滑仍翻页。

### Fixed

- 冷启动不再被 stale 的 `kernelState/kernelPid` 吞掉：启停入口按进程存活判断，状态不真实时先回写 stopped 再启动。
- 通知「停止」后状态同步落盘（`RuntimePrefs` 改同步 `commit`），磁贴与小组件随之刷新。
- 固定 `path_provider_android 2.2.23`，修复首次安装后打开配置目录失败（`ClassNotFoundException: android.content.Context`）。
- 快捷设置磁贴名称改为「clashdeck」，避免与系统开关混淆（应用与界面仍为 ClashDeck）。

### Tests

- `test/runtime_restart_test.dart`：合并重启、未运行时静默、500ms 去重。
- `test/save_restart_test.dart`：只有「当前配置 + 内核在跑」才重启。
- `test/delay_targets_test.dart`：从 proxies 取测速目标、异常结构兜底。
- `test/runtime_auto_delay_test.dart`：启动后自动测一次、手动测速进行中标记、重启后再测一次。
- `test/proxy_board_delay_test.dart`：测速完成 toast 数量、测速中入口禁用与 done/total 进度。
- `test/rule_row_card_test.dart`：标题只放中文名、类型在行尾、目标在第二行、紧凑模式只留色条与标题。
- Android：`KernelGate`、`WidgetCopy`、`RuntimePrefs` 的 JVM 单测（`./gradlew :app:testDebugUnitTest`）。

## [0.3.3] - 未发布

### Changed

- Pulse 打开手势改为「概览页右缘 28dp 手势带（带内 24dp 半透明把手 + 左箭头）起手左滑」，屏幕中部左右滑仍由 PageView 翻页；0.3.2 的「第 0 页禁用横向滚动」不再需要。
- TUN 模式强制 dns.enable: true：VpnService 把系统 DNS 指到 198.18.0.2，dns-hijack 依赖内核 DNS；用户在设置里关过 DNS 会静默断域名（延迟测速仍正常）。仅端口模式不受影响。
- 设置页在 TUN 模式下把「启用 DNS」显示为开启并拦截关闭操作，提示切到「仅代理端口」再关。
- IPv6 只在 YAML `ipv6: true` 时才把 v6 地址/路由加进 TUN（通过 intent extra 传给 VpnService），避免 v6 流量被吸进隧道后丢弃。

### Added

- 内核日志卡新增「诊断」入口：版本、运行模式、分流模式、全局出口、DEFAULT 当前出口、应用路由、DNS/TUN 关键项、TUN 服务状态、代理流量与最后 20 行日志，可一键复制（不含节点密码与订阅地址）。

### Fixed

- 概览页没有把版本号传给诊断面板，导致显示「未知版本」。
- 诊断面板读错 YAML key（`groups`），DEFAULT 当前出口一直显示「—」；改读 `proxy-groups`。
- 诊断面板不再依赖 `/sys/class/net/tun*/statistics`（应用 UID 被 SELinux 拒绝，真机恒为未知）：TUN 是否建立改看 `ClashVpnService.running`，流量改看内核 REST 的代理流量；删除对应的 tunStats 通道与概览黄条。

### Tests

- `test/runtime_config_test.dart`：TUN 强制开启 DNS、仅端口保留用户关闭、无 dns 段时补默认段。
- `test/settings_dns_guard_test.dart`：TUN 下点开关不写 false 且出现提示。
- `test/runtime_diagnostic_test.dart`：诊断文本字段（含 DEFAULT 出口、VpnService 状态、代理流量）。
- `test/pulse_entry_test.dart`：右缘手势带边界与阈值。
## [0.3.2] - 2026-11-19

### Changed

- Pulse 负一屏改为右侧 80% 抽屉：左滑跟手滑入，左侧露出一条压暗的概览；面板宽度按屏宽 80% 计算，右侧贴边直角、左侧圆角。
- 收起方式统一为：面板上向右拖（过 35% 或右甩 >300px/s）、点左侧暗区、点面板右上角 ×、系统返回键；不再使用整屏叠加层与「右滑返回」提示。
- 概览第一页禁用 `PageView` 横向滚动，修复左滑被分页手势吃掉、抽屉打不开的根因；配置 / 设置页仍可左右滑。
- Pulse 内容复用原卡片顺序（信息 / 节点测速 / 检查更新 / 运行状态），打开时隐藏底部悬浮岛，关闭后恢复且概览滚动位置不变。

### Tests

- `test/pulse_entry_test.dart` 覆盖抽屉宽度、跟手进度、开合阈值与分页物理；`test/pulse_drawer_test.dart` 覆盖 80% 宽度、暗区点击、收起位置与开合后滚动位置保持；`test/pulse_page_test.dart` 补右上 × 回调；删除已废弃的 `pulse_route_test.dart`。
## [0.3.1] - 2026-11-19

### Fixes

- 修复概览「停止内核」按钮比「启动内核」窄、矮：三种状态统一 46 高、铺满宽度、24 横向内边距与 14 圆角。
- 修复 Pulse 负一屏打不开：原入口依赖概览页 `onHorizontalDrag*`，被 `PageView` 的横向手势竞技场吃掉；改为监听第一页向右拖出 `overscroll`（≥96dp 或右甩 ≥350px/s）后打开，并新增 `PulseSwipeEntry`。

### Tests

- 新增 `test/pulse_entry_test.dart`（阈值、右拖触发、非首页不触发）与 `test/start_stop_button_test.dart`（三态同宽同高）；583 个测试全绿，UI 规范检查 0 基线。

## [0.3.0] - 2026-11-19

### Features

- 新增 Pulse 负一屏：概览左滑进入，玻璃卡片叠加层、节点批量测速与延迟胶囊。
- 新增检查更新与自动检查开关（读取 GitHub 最新正式版，只跳浏览器下载）。
- 支持从手机选择 YAML 文件导入，导入对话框保留「从文件导入」入口。

### Fixes

- 修复新建规则弹窗无法退出；编辑规则点遮罩即保存，非法内容不关闭。
- 修复左滑删除红块直角与层级错位、helper 文案截断、选中高亮变白与系统策略胶囊点不动。

### Refactor

- 删除交互统一走 SlidableRow + confirmDelete；规则行改胶囊卡、节点列表改行式。
- 统一弹窗 / 输入框 / 胶囊等共享组件，自定义点击反馈与页面过渡。

### Tests / CI

- 581 个测试全绿；UI 规范自检清零基线与禁用模式。
## [0.2.1] - 2026-11-18

### Features

- 新增规则四区（本地 / 在线 / GEO / 兜底）与区头快捷入口，规则行改为胶囊卡。
- 在线规则集面板：预置 Loyalsoldier / ACL4SSR 分组、自定义地址、导入预览（新建 / 更新 / 跳过）。
- GEO 面板：分类 chips + 搜索 + 自由输入 code，批量写入 GEOSITE 规则。
- 「默认」组更名为 `DEFAULT` 并迁移旧配置；目标组缺失时回落到 `DEFAULT`。
- 策略组：组卡新增「本组规则」区块、⋮ 直达编辑、左滑删除、规则胶囊可拖到组。
- 组内选择写入配置 sidecar，停止状态点胶囊也能切换并高亮。
- 「自动选择」组按测速选路；DIRECT / REJECT 等内置出站可加入策略组。
- 概览全局出口改为分区选择器（跟随内核默认 / 系统策略 / 策略组 / 节点）。
- 分应用代理选择页：加载骨架、异步分批送列表、应用图标与搜索。
- 订阅导入弹窗改为只收地址，「保存」后再询问是否立即同步。
- 新增 `AppTextArea` 多行文本域，统一弹窗宽度、输入框与按钮规范。
- 新增 `Motion` 动效 token 与第一批动效（展开 / 胶囊选中 / 启停 cross-fade）。

### Fixes

- 修复新建规则弹窗无法退出（P0）：新建时点遮罩 / × / 系统返回静默丢弃半成品，编辑时合法才保存、非法丢弃并提示「内容无效，未保存」。
- 编辑规则新增标题行删除入口（44dp、danger 色），与规则行左滑删除共用同一确认实现。
- 修复左滑删除红块直角、超出行卡与层级错位：`SlidableRow` 支持行卡圆角裁剪并统一四处用法。
- 修复新建配置弹窗 helper 文案被截断：helper / error 最多两行，超出省略。
- 应用新图标（pixel-cat + 蓝色轨道光弧），adaptive icon 背景 `#040406`。
- 修复空 `InkWell` 吞掉子 chip 点击、系统策略胶囊点不动、选中态变白的问题。
- 修复组内已选成员被删除后不高亮：选择前做存在性校验并按节点 / DIRECT / REJECT 回落。
- 修复规则目标选择器残留 `expand_more` 箭头、窄弹窗与按钮被键盘遮挡。
- 修复配置列表在 CI 上因 mtime 相同导致排序不稳定。
- 修复 YAML 编辑把 `/` 转义成 `\/` 导致内核解析失败。

### Performance

- 规则列表改 `SliverReorderableList` 惰性构建，520 条展开从约 894ms 降到约 260ms。
- 应用图标缓存改为 LRU 200，避免常驻内存增长。
- 配置页切换过渡与组内选择只重建变化的行。

### Refactor

- 共享组件：`EditDialog` / `ConfirmDialog` / `NoticeDialog` / `AppTextField` / `AppSearchField` / `AppInkWell` / `appRoute` / 胶囊组件 / 分区选择器。
- UI 自检改为 0 基线（禁止裸 `AlertDialog`、`InkWell`、`MaterialPageRoute`、`DropdownButton`、裸 `TextField`、`Checkbox*` 等）。
- 统一间距 / 圆角 / 图标刻度与字号走 `textTheme`，浅色主题选中胶囊加深。
- 规则行抽出的可识别名（`ruleTitleOf`）、成员顺序归一化（`member_order.dart`）与目标排序（`rule_targets.dart`）。

### Tests · CI

- 测试从 329 增至 517：动效、订阅弹窗、应用选择、图标缓存、组选择、成员顺序、导航转场、规则弹窗四条退出路径、左滑圆角与 helper 两行。
- UI 自检新增动画时长 / 多行文本 / 左滑 / 面板四类禁用（0 基线）。
- CI 失败用例写入 `$GITHUB_STEP_SUMMARY`；新增 UI 约定自检与零基线断言。
- 文档：README 用户向、`docs/DEVELOPMENT.md`、`docs/DESIGN_SYSTEM.md`。
