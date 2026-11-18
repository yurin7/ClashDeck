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
| 编辑（规则 / 策略组 / 节点 / 文本） | 编辑弹窗 | 宽 520 封顶 | 底部右对齐：取消 / 保存；**编辑态不含删除**（删除只走左滑） | 右上关闭、点遮罩、系统返回 |
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
- 规则行行尾固定两个动作：`swap_horiz`「换到别的组」（44dp 热区，点开即 TargetPickerSheet，选中即写回）与可选「更新规则集」；点行本体 = 编辑。
- 删除统一「左滑露出删除 → 确认弹窗」；不在 `⋮` 里、也不在编辑弹窗里放删除。
- 左滑只作用在行本体：组卡的滑区是**标题行**，规则行的滑区是**规则胶囊本体**；成员 chip 区不参与滑动。
- 编辑规则点遮罩即保存；校验不通过时弹 toast 且保持打开，只有右上「关闭」在合法时才退出。
- 抽屉 / sheet 顶部固定拖拽手柄；点击关闭按钮、下滑、点遮罩都可退出。
- 页面切换只做高亮与数字过渡（220ms），不重排列表。

### 5.1 点击反馈

- 所有自定义可点行（列表项、chip、下拉选项）用 `AppInkWell`（`lib/ui/widgets/app_ink.dart`）：
  overlay / splash 全透明，按下 120ms 缩到 0.985。
- `AppInkWell` 无任何回调时不创建 `InkWell`（否则空 `onTapUp` 会注册手势、吞掉子 chip 的点击）。
- M3 按钮（`FilledButton` / `TextButton`）保留原生 ripple；不要给它们套 `AppInkWell`。

### 5.2 动效

- 页面路由统一 `appRoute()`（`lib/ui/navigation.dart`）：进入 300ms `easeOutCubic`（右滑入 + 0.6→1 淡入），返回 260ms `easeInCubic`。
- 业务弹窗 `showAppDialog`：240ms fade + scale 0.96→1；底部 sheet 上滑 240ms。
- 状态切换（配置行、组内选中）：`AnimatedContainer` / `AnimatedSwitcher` 220ms，不位移列表顺序。

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
| `showModalBottomSheet(` | `showAppSheet` / `showSelectSheet` | `lib/ui/sheets.dart` |
| `showAppDialog(` 缺 `width:` | 传 `dialogWidthOf(context)` 或 `confirmDialogWidth(context)` | — |
| `AppDropdown(label: '目标…')` | `TargetSelectorField` + `showTargetPickerSheet` | — |

`test/ui_zero_baseline_test.dart` 对同一张表逐个模式统计计数并断言全 0；`test/ui_conventions_test.dart` 用样例源码覆盖命中/放行/注释/负向回顾。

## 7. 弹窗规范（可执行参数）

> 这一章是硬参数：`test/dialog_spec_test.dart` 会按这里的数字断言，偏离直接 fail。

### A. 编辑类弹窗（`EditDialog` / `showEditDialog`）

- **尺寸**：宽 `min(520, 屏宽-64)`；高自适应，封顶 `min(屏高*0.8, 720)`。内容超高时**只滚内容区**，标题栏与底部按钮固定。
- **结构**：标题 `20sp / w600`；可选副标题 `13sp`、`60%` 不透明度；右上「关闭」图标（44dp 热区）；内容 padding `24 水平 / 20 垂直`；底部按钮区 padding `24 / 16`，与内容之间一条 `Divider(height: 1)`。
- **按钮**：底部右对齐；主按钮 `FilledButton` 高 44、最小宽 96、圆角 12；次按钮 `TextButton` 在其左侧、间距 12；**最多两个按钮**（取消 / 保存）。编辑态**不放删除按钮**，删除统一走左滑；`EditDialog(showFooter: false)` 用于「点遮罩即保存」的轻量编辑（如规则编辑）。
- **输入框**：统一 `fields.dart`（高 44、圆角 12、label 浮动、错误文本 12sp）。
- **多行文本域**：粘贴多行链接、订阅地址、导入 YAML 等大段文本统一用 `AppTextArea`：宽度撑满内容区、高度约 `0.8 × 可用宽`（`110–320` 之间 clamp）、自动换行、内容超出在框内滚动；不要再用 `minLines/maxLines` 手写高度。`showTextInputDialog(area: true)` 是它的弹窗封装。
- **关闭**：`barrierDismissible: true` 仅限非破坏性表单；有未保存改动时拦截并二次确认。规则编辑例外：`barrierDismissible: false` + `onBarrierTap`——内容合法时点遮罩直接保存并关闭，非法时 toast「请填写匹配内容」并保持打开。
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
| 编辑规则 | `showRuleEditDialog` + `EditDialog(showFooter: false)` | 点遮罩即保存；无保存/取消/删除按钮；高级内置默认折叠 |
| 规则换组 | 行尾 `swap_horiz` → `showTargetPickerSheet` | 分区：策略组 → 系统策略 → 高级内置（折叠） |
| 编辑策略组 | `showEditDialog` + `EditDialog` | 组名 / 类型 / 测速参数；无「隐藏」开关 |
| 新建组 | `showEditDialog` + `EditDialog` | 组名 + DIRECT/REJECT 高亮行 |
| 单行输入 | `showTextInputDialog` | 宽 520；输入框撑满；helper 不截断 |
| 导入（规则 / 规则集 / 订阅） | `showEditDialog` 或多行粘贴面板 | 目标统一 DEFAULT |
| 订阅地址 | `showSubscriptionDialog` | 只收地址；取消 / 保存；保存后再问「是否立即同步此订阅？」 |
| 多行文本（粘贴链接 / YAML） | `AppTextArea`（或 `showTextInputDialog(area: true)`） | 宽度撑满、高度 0.8×宽、框内滚动 |
| 选择节点（加成员） | `showSelectSheet` + `NodePickerSheet` | 分区：系统策略 → 节点 → 策略组 |
| 全局出口 | `showSelectSheet` + `SectionedPicker` | 分区：内核默认 → 系统策略 → 策略组 → 节点 |
| 选择规则（挂到组） | `showSelectSheet` + `rule_picker_sheet` | 行内 `RuleChip` |
| 移动到组（规则） | `showSelectSheet` + 组列表 | `GroupChip` 行 |
| 删除确认 | `showConfirmDialog` | 破坏性：确定按钮 error 色；入口只有左滑 |
| 忙碌 / 进度 | `showAppDialog(width:)` + `BusyDialog` | `barrierDismissible: false`；可带进度与取消 |
| 撤销确认 | `showConfirmDialog` | 文案说明影响范围，非破坏性样式 |
