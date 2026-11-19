# ClashDeck 界面规范（v1）

> 这份文档是「长什么样」的唯一出处。新增界面先在这里找到对应类型，再复用共享组件；
> `tool/check_ui_conventions.dart` 会按这里的硬性规则扫源码，CI 会跑 `--check`。

## 1. 三类容器

| 类型 | 组件 | 宽度 / 高度 | 圆角 | 标题行 | 按钮 |
| --- | --- | --- | --- | --- | --- |
| 编辑弹窗 | `EditDialog` / `showEditDialog` | 宽 `min(520, 屏宽-64)`，高 ≤ `min(屏高*0.8, 720)` | `Radiuses.xl` | 左标题、右「关闭」 | 底部右对齐：取消 / 主按钮 |
| 选择面板 | `showSelectSheet`（内部 `showAppSheet`） | 高 `min(屏高*0.72, 640)` | 顶部 `Radiuses.xl`（bottom sheet 默认） | 拖拽手柄 + 左标题/副标题、右「关闭」 | 底部常驻：左侧可选操作，右侧取消/确认 |
| 确认弹窗 | `ConfirmDialog` / `showConfirmDialog` | 宽 `min(400, 屏宽-64)`，高自适应 | `Radiuses.xl` | 只有标题 + ≤2 行说明 | 右对齐：取消 / 危险操作（error 色） |

- 输入框统一 `AppTextField`（高 44、圆角 `Radiuses.md`、`fieldDecoration`）。
- 内容超长时**容器高度不变**，内部滚动；底部按钮不随内容滚走。
- 小屏按比例缩，大屏封顶（弹窗 520、sheet 640）。

## 2. 操作类型矩阵

| 操作 | 用什么 | 尺寸 | 按钮排布 | 关闭方式 |
| --- | --- | --- | --- | --- |
| 编辑（规则 / 策略组 / 节点 / 文本） | 编辑弹窗 | 宽 520 封顶 | 底部右对齐：取消 / 保存；**编辑态默认不含删除**（删除走左滑；规则编辑例外：标题行右侧删除图标） | 右上关闭、点遮罩、系统返回 |
| 选择（节点 / 规则 / 规则集 / GEO） | 选择面板 | 高 72% 屏高封顶 | 底部：取消 / 「加入 N 个」；顶部全选/反选/清空 | 右上关闭、下滑、点遮罩 |
| 确认（删除 / 覆盖） | 确认弹窗 | 宽 400 封顶 | 右对齐：取消 / 危险操作 | 右上关闭、点遮罩 |
| 菜单（节点 ⋮、配置长按） | 菜单型 sheet（`showAppSheet` 不传 title） | 内容自适应，≤72% 屏高 | 无底部按钮 | 点任意项、点遮罩、下滑 |
| 删除（配置 / 策略组） | 左滑露出「删除」→ 确认弹窗 | 行内 | 行尾按钮 | 滑回、点遮罩 |
| 导入（规则 / 规则集 / 订阅） | 编辑弹窗或选择面板 | 同上 | 右对齐：取消 / 导入 | 右上关闭 |

## 3. 选择与选中态

- **多选一律用高亮行**（`SelectableTile` / `NameChip` 的 `selected`）：
  底色 `primary` 12%、描边 45%。**不画行尾 ✓**（只靠紫底紫边表达选中），也**不再使用 `Checkbox` / `CheckboxListTile`。**
- 只有设置里的开关类（`Switch`）保留。
- 多选场景：节点、规则、规则集预选、GEO 词库 —— 全部同一套高亮行。
- 已加入 / 不可选：整行 55% 透明度、点击无响应，右侧可带「已添加」「已在组内」状态胶囊。
- 分区顺序固定：**系统策略 → 节点 → 策略组**；0 节点时「系统策略」段照常显示。
- 面板底部计数与按钮文案用同一个数：`已选 N` / `加入 N 个`。

## 4. 图标与颜色

- 系统策略：`DIRECT` 绿（`scheme.tertiary`）、`REJECT` 红（`scheme.error`）、
  `REJECT-DROP` 灰（`scheme.onSurfaceVariant`）+「不常用」；图标来自 `builtinIcon(name)`。
- 四区色（规则页）：本地 `primary`、在线 `tertiary`、GEO `secondary`、兜底 `error`。
- 胶囊统一 `chips.dart`：`NodeChip` / `RuleChip` / `GroupChip` / `SystemPolicyChip` / `NameChip`，
  外用 `ChipShell`；不要各自写 `Container` 样式。
- 胶囊选中态唯一强调色 = `scheme.primary`（品牌紫）：底色 16%、描边 1.4、文字同色；
  **禁止**拿 `onSurface`/白色当选中色。未选中一律中性底 + `outlineVariant` 细边，不做强调。
- 组内成员（节点 / 策略组 / 系统策略）都走同一个 `onSelectMember(name)`；同组同时只有一个选中。
- **组内选择回落**：sidecar 里记住的成员只有在仍属于该组时才生效；否则自动选组内第一个节点，没有节点再 `DIRECT` → `REJECT`。成员被删光后重新加节点不会出现「没有任何高亮」。规则在 `lib/core/edit/member_order.dart` 的 `defaultGroupSelection`。
- **组内成员顺序固定**：代理节点 → 策略组等其它成员 → `DIRECT` → `REJECT`（同级保持原相对顺序）。每次加/删成员或整表写入都按此归一化，UI 顺序与 YAML 文本一致；拖动成员进组后，本组当前出口自动切到该节点。

## 5. 交互约定

- `⋮` 只表示「设置 / 编辑」，不承载导入、隐藏等动作；**规则行不再有 `⋮`**。
- 规则行：左侧 4dp 目标色条（DIRECT 绿 / REJECT 红 / 策略组主色 / 其它灰），标题只放规则值或规则集显示名，类型小标签在行尾，目标 chip 在第二行；行尾两个动作是 `swap_horiz`「换到别的组」（44dp 热区，点开即 TargetPickerSheet，选中即写回）与可选「更新规则集」；点行本体 = 规则详情（完整名字 / payload + 编辑、换组入口）。
- 删除统一「左滑露出删除 → 确认弹窗」；不在 `⋮` 里。**唯一例外**：编辑规则时标题行右侧的删除图标（44dp、danger 色、仅编辑态）。所有删除入口共用 `lib/ui/widgets/delete_confirm.dart` 的 `confirmDelete`（`danger: true`，可带引用提示）。
- 左滑只作用在行本体：组卡的滑区是**标题行**，规则行的滑区是**规则胶囊本体**，节点行的滑区是整行 `NodeRow`；成员 chip 区不参与滑动。
- 左滑删除必须把内容裁到行卡圆角：`SlidableRow(borderRadius: 行卡半径)`（必传），红块不超出行 rect，行与行之间的留白由外层 `Padding` 负责（不要塞进滑动区）。滑出宽度 80，`open`/关闭 220ms。
- 点「删除」先收起该行，再弹确认；确认框取消后行**保持收起**。同一列表同一时刻只允许一行展开（单行互斥）。
- 删除节点时确认框附带引用提示（「N 个组引用了它：…，删除后会一起移除」）；删除策略组只删组、不动节点。

- 规则编辑的关闭语义：**新建**时点遮罩 / 右上 × / 系统返回一律退出，空或半填直接丢弃、不提示；**编辑**时合法就保存并关闭，非法则丢弃改动、toast「内容无效，未保存」并关闭。
- 抽屉 / sheet 顶部固定拖拽手柄；点击关闭按钮、下滑、点遮罩都可退出。
- 页面切换只做高亮与数字过渡（220ms），不重排列表。

### 5.1 点击反馈

- 所有自定义可点行（列表项、chip、下拉选项）用 `AppInkWell`（`lib/ui/widgets/app_ink.dart`）：
  overlay / splash 全透明，按下 120ms 缩到 0.985。
- `AppInkWell` 无任何回调时不创建 `InkWell`（否则空 `onTapUp` 会注册手势、吞掉子 chip 的点击）。
- M3 按钮（`FilledButton` / `TextButton`）保留原生 ripple；不要给它们套 `AppInkWell`。

### 5.2 动效

页面路由统一 `appRoute()`（`lib/ui/navigation.dart`）：进入 300ms `easeOutCubic`（右滑入 + 0.6→1 淡入），返回 260ms `easeInCubic`。
业务弹窗 `showAppDialog` 240ms fade + scale 0.96→1；底部 sheet 上滑 240ms。

组件内动画一律走 `Motion`（`lib/ui/motion.dart`），不在业务代码里散写 `Duration`：

| token | normal | calm（减少动画） | 用途 |
| --- | --- | --- | --- |
| `fast` | 140ms | 60ms | 按下反馈、按钮 cross-fade |
| `chip` | 140ms | 60ms | chip 选中/取消的颜色、描边、缩放 |
| `arrow` | 180ms | 60ms | 展开箭头旋转 |
| `expand` | 220ms | 60ms | 区展开折叠、成员/组卡增删的高度变化 |
| `page` | 300ms | 60ms | 仅记录参考值；`appRoute` 实际固定 300/260ms |

- 曲线：入场 `Motion.enter` = `easeOutCubic`，退场 `Motion.exit` = `easeInCubic`；仅 toast / 底部 sheet 允许轻微 `easeOutBack`。
- `Motion.of(context)` 读 `MediaQuery.disableAnimations`：系统开启「减少动画」时全部降到 `calm`（60ms）；页面路由由 `appRoute` 固定，不随该 token 变化。
- 允许的动效点**只有这些**：区展开 `AnimatedSize` + 箭头 `AnimatedRotation`；成员/组卡增删的单项 `MotionEntrance`（fade + 0.98→1）；chip 选中 `AnimatedContainer` + scale 0.98→1（不发光、不抖动）；内核启停 `StartStopButton`（`lib/ui/widgets/start_stop_button.dart`）cross-fade。
- 禁止：整页缩放、整列表 fade 入场、并行超过 2 个动画、单项超过 350ms、动画回调里 `setState` 整表。动画只重建自身；大列表继续用惰性 sliver。

## 6. 禁止清单（CI 自检，0 基线）

`dart run tool/check_ui_conventions.dart --check` 扫 `lib/ui`，下列模式**必须为 0 处**（没有 allowlist 递减，命中即失败）：

| 模式 | 替代 | 允许出现的文件 |
| --- | --- | --- |
| `AlertDialog(` | `EditDialog` / `ConfirmDialog` / `NoticeDialog` / `TextInputDialog` | `lib/ui/widgets/edit_dialog.dart`（`_NoticeDialog`） |
| `Dialog(` | `showAppDialog` + `BusyDialog` / `EditDialog` | `lib/ui/widgets/busy_dialog.dart` |
| `SimpleDialog(` / `SimpleDialogOption(` | `showSelectSheet` + `SelectableTile` | — |
| `InkWell(` / `InkResponse(` | `AppInkWell` | `lib/ui/widgets/app_ink.dart` |
| `MaterialPageRoute(` / `MaterialPageRoute<` | `appRoute()` | `lib/ui/navigation.dart` |
| `TextField(` | `AppTextField`（或 `AppSearchField`） | `lib/ui/fields.dart` |
| `DropdownButton(` / `DropdownButton<` | `AppDropdown` | `lib/ui/dropdown.dart` |
| `Checkbox(` / `Checkbox.adaptive(` / `CheckboxListTile(` / `CheckboxListTile.adaptive(` | 高亮行 `SelectableTile` / `NameChip` | — |
| `showDialog<` | `showAppDialog` | — |
| `Dismissible(` | `SlidableRow`（左滑） | — |
| `onHorizontalDragUpdate:` | `SlidableRow`（左滑手势只在共享组件里实现） | `lib/ui/widgets.dart` |
| `maxLines: null` | `AppTextArea` / `AppTextField(expands: true)` | `lib/ui/fields.dart` |
| `duration: const Duration(` | `Motion` token（`lib/ui/motion.dart`） | `lib/ui/motion.dart` |
| `PickerSheetScaffold(` | `showSectionedPicker` / `showSelectSheet` | `lib/ui/sheets/` 与 `lib/ui/rule_picker_sheet.dart` |
| `showModalBottomSheet(` | `showAppSheet` / `showSelectSheet` | `lib/ui/sheets.dart` |
| `showAppDialog(` 缺 `width:` | 传 `dialogWidthOf(context)` 或 `confirmDialogWidth(context)` | — |
| `AppDropdown(label: '目标…')` | `TargetSelectorField` + `showTargetPickerSheet` | — |

`test/ui_zero_baseline_test.dart` 对同一张表逐个模式统计计数并断言全 0；`test/ui_conventions_test.dart` 用样例源码覆盖命中/放行/注释/负向回顾。

## 7. 弹窗规范（可执行参数）

> 这一章是硬参数：`test/dialog_spec_test.dart` 会按这里的数字断言，偏离直接 fail。

### A. 编辑类弹窗（`EditDialog` / `showEditDialog`）

- **尺寸**：宽 `min(520, 屏宽-64)`；高自适应，封顶 `min(屏高*0.8, 720)`。内容超高时**只滚内容区**，标题栏与底部按钮固定。
- **结构**：标题 `20sp / w600`；可选副标题 `13sp`、`60%` 不透明度；右上「关闭」图标（44dp 热区）；内容 padding `24 水平 / 20 垂直`；底部按钮区 padding `24 / 16`，与内容之间一条 `Divider(height: 1)`。
- **按钮**：底部右对齐；主按钮 `FilledButton` 高 44、最小宽 96、圆角 12；次按钮 `TextButton` 在其左侧、间距 12；**最多两个按钮**（取消 / 保存）。编辑态默认**不放删除按钮**，删除统一走左滑；**唯一例外**是编辑规则：删除图标放标题行右侧（`EditDialog.headerActions`），不与底部按钮混排。规则弹窗的底部按钮只在**新建**时出现（取消 / 添加）；编辑态用 `EditDialog(showFooter: false)`，点遮罩 / × 即保存。
- **输入框**：统一 `fields.dart`（高 44、圆角 12、label 浮动、错误文本 12sp）；helper / error 最多两行（`helperMaxLines/errorMaxLines = 2`），超出省略，不允许把按钮挤出弹窗。
- **多行文本域**：粘贴多行链接、订阅地址、导入 YAML 等大段文本统一用 `AppTextArea`：宽度撑满内容区、高度约 `0.8 × 可用宽`（`110–320` 之间 clamp）、自动换行、内容超出在框内滚动；不要再用 `minLines/maxLines` 手写高度。`showTextInputDialog(area: true)` 是它的弹窗封装。
- **关闭**：`barrierDismissible: true` 仅限非破坏性表单；有未保存改动时拦截并二次确认。规则编辑例外：`barrierDismissible: false` + `onBarrierTap`——**新建**时点遮罩 / × / 系统返回直接丢弃退出（不校验、不拦），**编辑**时内容合法就保存并关闭、非法则丢弃改动 + toast「内容无效，未保存」并关闭。
- **动画**：240ms fade + scale 0.96→1（`app_dialog.dart`）。

### B. 选择类底部弹窗（`showSelectSheet` / 节点选择面板）

- **尺寸**：高 `min(屏高*0.72, 640)`；顶部圆角 24；顶部 `4×40` 拖拽手柄；标题行左标题、右关闭。
- **底部操作栏常驻**：分隔线 + 左侧辅助动作（如「新建节点」）+ 右侧「取消 / 加入 N 个」。
- **列表**：搜索框、分区标题 `13sp / 60%`、行高 56–64、选中态高亮无框（`SelectableTile`）。
- **键盘**：弹起时内容区收缩、操作栏上移，不遮挡输入框。
- 表单里的目标选择（`TargetSelectorField`）只显示当前目标的 `NameChip`，**不再画 `expand_more` 箭头**；整行可点，点开是同一个选择面板。

### C. 确认类弹窗（`ConfirmDialog` / `showConfirmDialog`）

- **尺寸**：宽 `min(400, 屏宽-64)`；标题 + **2 行以内**正文。
- **按钮**：右对齐「取消 / 确定」；破坏性操作确定按钮用 `error` 色。
- **关闭**：`barrierDismissible: false`，必须显式点按钮。

### D. 菜单 / 动作面板（`showAppSheet` 不传 title）

- 高自适应、`≤ 0.6 屏高`；行高 52；无标题或小标题；每行左图标 + 文案；破坏性行红色；点外关闭。

### E. 自检规则（0 基线）

- 业务代码只允许这些封装：`app_dialog.dart`（`showAppDialog` / `showConfirmDialog` / `dialogWidthOf` / `confirmDialogWidth`）、
  `widgets/edit_dialog.dart`（`EditDialog` / `ConfirmDialog` / `NoticeDialog` / `showNoticeDialog`）、
  `widgets/text_input_dialog.dart`（`showTextInputDialog`）、`widgets/busy_dialog.dart`（`BusyDialog`）、
  `sheets.dart`（`showAppSheet`）、`widgets/select_sheet.dart`（`showSelectSheet`）。
- 第 6 章那张表就是自检清单，**计数必须为 0**；`tool/ui_conventions_baseline.txt` 已删除，`--update-baseline` 只打印「全部规则为 0 基线」。
- 测试：`test/ui_conventions_test.dart`（规则样例）、`test/ui_zero_baseline_test.dart`（真实目录 0 命中）、
  `test/dialog_spec_test.dart`（宽度/高度/遮罩）、`test/navigation_test.dart`（`appRoute` 时长与曲线）、`test/dialog_width_test.dart`（全站弹窗同宽）。

## 8. 场景 → 组件对照表

| 场景 | 组件 | 说明 |
| --- | --- | --- |
| 编辑节点 | `showEditDialog` + `EditDialog` | 内容为节点表单；底部 取消 / 保存 |
| 编辑规则 | `showRuleEditDialog` + `EditDialog(showFooter: false)` | 编辑：点遮罩 / × / 返回合法即保存、非法丢弃 + toast；新建：底部 取消 / 添加，点遮罩 / × / 返回静默丢弃；无保存/取消文字按钮（新建除外）；删除在标题行右侧（仅编辑态）；高级内置默认折叠 |
| 规则换组 | 行尾 `swap_horiz` → `showTargetPickerSheet` | 分区：策略组 → 系统策略 → 高级内置（折叠） |
| 编辑策略组 | `showEditDialog` + `EditDialog` | 组名 / 类型 / 测速参数；无「隐藏」开关 |
| 新建组 | `showEditDialog` + `EditDialog` | 组名 + DIRECT/REJECT 高亮行 |
| 单行输入 | `showTextInputDialog` | 宽 520；输入框撑满；helper 不截断 |
| 导入（规则 / 规则集 / 订阅） | `showEditDialog` 或多行粘贴面板 | 目标统一 DEFAULT |
| 导入配置（概览） | `_ImportDialog`（名称 + 多行文本域） | 底部操作行最左「从文件导入」按钮打开系统选择器，选中后回填名称与文本；文件只收 .yaml/.yml/.txt、≤2MB、UTF-8，文件名做配置名（重名自动 `-2`） |
| 订阅地址 | `showSubscriptionDialog` | 只收地址；取消 / 保存；保存后再问「是否立即同步此订阅？」 |
| Pulse 抽屉 | `PulseDrawer`（`lib/ui/pulse_drawer.dart`）+ 右缘把手（`lib/ui/widgets/pulse_edge_handle.dart`） | 面板宽 = 屏宽 × 0.8 贴右，左侧 20% 露出压暗概览（黑 45%、概览 scale 0.98）；**只有概览页右缘 28dp 手势带**（带内 24dp 半透明把手 + 左箭头）起手左滑才跟手拉抽屉，屏幕中部左右滑仍由 PageView 翻页；`progress > 0.35 || velocity < -300` 打开（240ms easeOutCubic），否则回弹；右拖 `progress < 0.65 || velocity > 300`、点左侧暗区、点右上 ×、系统返回均可收起；打开时隐藏底部悬浮岛，概览滚动位置保持 |
| 节点测速（Pulse） | 测速卡（`lib/ui/pulse_page.dart`） | 内核未运行且无缓存时只显示说明 +「启动内核」；有缓存显示「上次结果 · MM-DD HH:mm」+ 组筛选 / 全选 / 结果行；测速中才显示雷达进度；并发 4、`timeout=5000`、`url=http://www.gstatic.com/generate_204`；结果按延迟升序、失败灰「超时」、阈值 <200 绿 / <500 黄 / 其它红 |
| 运行状态（Pulse） | 运行状态卡 | 内核状态、运行时长、连接数（仅 Pulse 可见时 3s 轮询）、当前配置、GLOBAL 出口 |
| 检查更新（设置页·其它） | `_ActionRow` + `showUpdateDialog` | 版本/发布日期/说明最多 6 行高滚动；「去下载」只跳浏览器 Release 页，不做应用内下载；自动检查默认关、24h 节流、失败静默 |
| 多行文本（粘贴链接 / YAML） | `AppTextArea`（或 `showTextInputDialog(area: true)`） | 宽度撑满、高度 0.8×宽、框内滚动 |
| 选择节点（加成员） | `showSelectSheet` + `NodePickerSheet` | 分区：系统策略 → 节点 → 策略组 |
| 全局出口 | `showSelectSheet` + `SectionedPicker` | 分区：内核默认 → 系统策略 → 策略组 → 节点 |
| 选择规则（挂到组） | `showSelectSheet` + `rule_picker_sheet` | 行内 `RuleChip` |
| 移动到组（规则） | `showSelectSheet` + 组列表 | `GroupChip` 行 |
| 节点列表 | `NodeRow`（`lib/ui/widgets/node_row.dart`） | 行式：协议方块 + 名称 + 协议·延迟 + 当前徽章 + ⋮；点行编辑、长按拖拽、左滑删除 |
| 删除确认 | `confirmDelete`（`lib/ui/widgets/delete_confirm.dart`） | 破坏性：`danger: true`；入口：配置 / 策略组 / 规则 / 节点左滑、编辑规则标题行删除；节点确认带引用组提示 |
| 忙碌 / 进度 | `showAppDialog(width:)` + `BusyDialog` | `barrierDismissible: false`；可带进度与取消 |
| 撤销确认 | `showConfirmDialog` | 文案说明影响范围，非破坏性样式 |
