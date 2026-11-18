# 更新日志

只记录技术改动；用户向说明见 [README](README.md)。格式参考 Keep a Changelog。

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
