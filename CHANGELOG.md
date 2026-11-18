# 更新日志

只记录技术改动；用户向说明见 [README](README.md)。格式参考 Keep a Changelog。

## [0.2.0] - 2026-11-18

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

- 测试从 329 增至 507：动效、订阅弹窗、应用选择、图标缓存、组选择、成员顺序、导航转场等。
- UI 自检新增动画时长 / 多行文本 / 左滑 / 面板四类禁用（0 基线）。
- CI 失败用例写入 `$GITHUB_STEP_SUMMARY`；新增 UI 约定自检与零基线断言。
- 文档：README 用户向、`docs/DEVELOPMENT.md`、`docs/DESIGN_SYSTEM.md`。
