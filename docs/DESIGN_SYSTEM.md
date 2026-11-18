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
| 编辑（规则 / 策略组 / 节点 / 文本） | 编辑弹窗 | 宽 520 封顶 | 底部右对齐：取消 / 保存；编辑态左下「删除」 | 右上关闭、点遮罩、系统返回 |
| 选择（节点 / 规则 / 规则集 / GEO） | 选择面板 | 高 72% 屏高封顶 | 底部：取消 / 「加入 N 个」；顶部全选/反选/清空 | 右上关闭、下滑、点遮罩 |
| 确认（删除 / 覆盖） | 确认弹窗 | 宽 520 封顶 | 右对齐：取消 / 危险操作 | 右上关闭、点遮罩 |
| 菜单（节点 ⋮、配置长按） | 菜单型 sheet（`showAppSheet` 不传 title） | 内容自适应，≤72% 屏高 | 无底部按钮 | 点任意项、点遮罩、下滑 |
| 删除（配置 / 策略组） | 左滑露出「删除」→ 确认弹窗 | 行内 | 行尾按钮 | 滑回、点遮罩 |
| 导入（规则 / 规则集 / 订阅） | 编辑弹窗或选择面板 | 同上 | 右对齐：取消 / 导入 | 右上关闭 |

## 3. 选择与选中态

- **多选一律用高亮行**（`SelectableTile` / `NameChip` 的 `selected`）：
  底色 `primary` 12%、描边 45%、行尾 ✓。**不再使用 `Checkbox` / `CheckboxListTile`。**
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

## 5. 交互约定

- `⋮` 只表示「设置 / 编辑」，不承载导入、隐藏等动作。
- 删除统一「左滑露出删除 → 确认弹窗」；不在 `⋮` 里放删除。
- 抽屉 / sheet 顶部固定拖拽手柄；点击关闭按钮、下滑、点遮罩都可退出。
- 页面切换只做高亮与数字过渡（220ms），不重排列表。

## 6. 禁止清单（CI 自检）

`dart run tool/check_ui_conventions.dart --check` 会拦：

1. `lib/ui` 下出现 `Checkbox(` / `CheckboxListTile(`；
2. 除 `lib/ui/sheets.dart` 外直接调用 `showModalBottomSheet(`；
3. 任何 `showDialog<`（统一走 `showAppDialog`）；
4. `AlertDialog(` 只允许出现在共享封装里（当前基线见 `tool/ui_conventions_baseline.txt`，只减不增）；
5. `showAppDialog(` 未传 `width:`（同样按基线只减不增）。

改完跑一遍 `--update-baseline` 只会**降低**计数；CI 只跑 `--check`。

## 7. 弹窗规范（可执行参数）

> 这一章是硬参数：`test/dialog_spec_test.dart` 会按这里的数字断言，偏离直接 fail。

### A. 编辑类弹窗（`EditDialog` / `showEditDialog`）

- **尺寸**：宽 `min(520, 屏宽-64)`；高自适应，封顶 `min(屏高*0.8, 720)`。内容超高时**只滚内容区**，标题栏与底部按钮固定。
- **结构**：标题 `20sp / w600`；可选副标题 `13sp`、`60%` 不透明度；右上「关闭」图标（44dp 热区）；内容 padding `24 水平 / 20 垂直`；底部按钮区 padding `24 / 16`，与内容之间一条 `Divider(height: 1)`。
- **按钮**：底部右对齐；主按钮 `FilledButton` 高 44、最小宽 96、圆角 12；次按钮 `TextButton` 在其左侧、间距 12；**最多两个按钮**（取消 / 保存）。删除类操作放内容底部左侧（`TextButton` + error 色）或走左滑删除，不在按钮区出现第三个按钮。
- **输入框**：统一 `fields.dart`（高 44、圆角 12、label 浮动、错误文本 12sp）。
- **关闭**：`barrierDismissible: true` 仅限非破坏性表单；有未保存改动时拦截并二次确认。
- **动画**：240ms fade + scale 0.96→1（`app_dialog.dart`）。

### B. 选择类底部弹窗（`showSelectSheet` / 节点选择面板）

- **尺寸**：高 `min(屏高*0.72, 640)`；顶部圆角 24；顶部 `4×40` 拖拽手柄；标题行左标题、右关闭。
- **底部操作栏常驻**：分隔线 + 左侧辅助动作（如「新建节点」）+ 右侧「取消 / 加入 N 个」。
- **列表**：搜索框、分区标题 `13sp / 60%`、行高 56–64、选中态高亮无框（`SelectableTile`）。
- **键盘**：弹起时内容区收缩、操作栏上移，不遮挡输入框。

### C. 确认类弹窗（`ConfirmDialog` / `showConfirmDialog`）

- **尺寸**：宽 `min(400, 屏宽-64)`；标题 + **2 行以内**正文。
- **按钮**：右对齐「取消 / 确定」；破坏性操作确定按钮用 `error` 色。
- **关闭**：`barrierDismissible: false`，必须显式点按钮。

### D. 菜单 / 动作面板（`showAppSheet` 不传 title）

- 高自适应、`≤ 0.6 屏高`；行高 52；无标题或小标题；每行左图标 + 文案；破坏性行红色；点外关闭。

### E. 自检规则

- 业务代码只允许 `EditDialog` / `ConfirmDialog` / `showSelectSheet` 三种封装：
  `lib/ui/app_dialog.dart`（通用）、`lib/ui/widgets/edit_dialog.dart`、`lib/ui/widgets/select_sheet.dart`。
- 禁止裸 `showDialog<`、`showModalBottomSheet(`、`AlertDialog(`、`Checkbox(`、`CheckboxListTile(`；
  例外只允许出现在上述共享封装内，并按 `tool/ui_conventions_baseline.txt` 只减不增。
- `test/dialog_spec_test.dart` 断言：`EditDialog` 宽 `min(520, 屏宽-64)`、高 `≤ min(0.8*屏高, 720)`、按钮排布；
  `ConfirmDialog` 宽 `min(400, 屏宽-64)`、点遮罩不关闭；`showSelectSheet` 高 `≤ 0.72 屏高`。

## 8. 场景 → 组件对照表

| 场景 | 组件 | 说明 |
| --- | --- | --- |
| 编辑节点 | `showEditDialog` + `EditDialog` | 内容为节点表单；底部 取消 / 保存 |
| 编辑规则 | `showEditDialog` + `EditDialog` | 宽同 520；高级内置默认折叠 |
| 编辑策略组 | `showEditDialog` + `EditDialog` | 组名 / 类型 / 测速参数；无「隐藏」开关 |
| 新建组 | `showEditDialog` + `EditDialog` | 组名 + DIRECT/REJECT 高亮行 |
| 导入（规则 / 规则集 / 订阅） | `showEditDialog` 或多行粘贴面板 | 目标统一 DEFAULT |
| 选择节点（加成员） | `showSelectSheet` + `NodePickerSheet` | 分区：系统策略 → 节点 → 策略组 |
| 选择规则（挂到组） | `showSelectSheet` + `rule_picker_sheet` | 行内 `RuleChip` |
| 移动到组（规则） | `showSelectSheet` + 组列表 | `GroupChip` 行 |
| 删除确认 | `showConfirmDialog` | 破坏性：确定按钮 error 色 |
| 撤销确认 | `showConfirmDialog` | 文案说明影响范围，非破坏性样式 |
