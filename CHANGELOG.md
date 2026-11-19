# 更新日志

只记录技术改动；用户向说明见 [README](README.md)。格式参考 Keep a Changelog。

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
