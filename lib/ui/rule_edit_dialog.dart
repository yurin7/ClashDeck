import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/rule_types.dart';
import 'app_dialog.dart';
import 'dropdown.dart';
import 'fields.dart';
import 'widgets/edit_dialog.dart';
import 'widgets/target_selector_field.dart';
import 'toast.dart';

/// 规则编辑对话框的输入结果。
class RuleDraft {
  const RuleDraft({
    required this.type,
    required this.payload,
    required this.target,
    required this.noResolve,
  });

  final String type;
  final String payload;
  final String target;
  final bool noResolve;
}

/// 外部持有的「当前草稿」句柄。
///
/// 点遮罩自动保存时，`showRuleEditDialog` 在 barrier 回调里读它：
/// 校验不过（匹配内容为空）就是 null，不关闭弹窗。
class RuleDraftHandle {
  RuleDraft? draft;
}

/// 打开规则编辑弹窗：没有底部按钮；编辑态点遮罩 / 右上 × 即保存并关闭，
/// 新建态点遮罩 / × / 系统返回一律静默丢弃（半成品不拦退出）。
///
/// 删除只出现在「编辑已有规则」的标题行右侧，确认后由 [onDelete] 落库；
/// 规则行左滑删除调用同一个 [onDelete]，两个入口共用一套实现。
Future<RuleDraft?> showRuleEditDialog(
  BuildContext context, {
  String? initialType,
  String? initialPayload,
  String? initialTarget,
  bool initialNoResolve = false,
  required List<String> targets,
  List<String> otherBuiltins = const <String>[],
  required bool isNew,
  Future<bool> Function()? onDelete,
}) {
  final handle = RuleDraftHandle();
  return showAppDialog<RuleDraft>(
    context,
    width: dialogWidthOf(context),
    barrierDismissible: false,
    onBarrierTap: () {
      // 新建规则是「半成品」：点外面/返回一律丢弃，不校验、不拦退出。
      if (isNew) return const BarrierAction<RuleDraft>.close(null);
      final draft = handle.draft;
      if (draft != null) return BarrierAction<RuleDraft>.close(draft);
      // 编辑态非法：丢弃改动并提示，不让无效内容落库。
      showToast(context, '内容无效，未保存');
      return const BarrierAction<RuleDraft>.close(null);
    },
    builder: (_) => RuleEditDialog(
      initialType: initialType,
      initialPayload: initialPayload,
      initialTarget: initialTarget,
      initialNoResolve: initialNoResolve,
      targets: targets,
      otherBuiltins: otherBuiltins,
      isNew: isNew,
      handle: handle,
      onDelete: onDelete,
    ),
  );
}

/// 编辑/新建一条规则。
///
/// 用 StatefulWidget 而不是 `showDialog` + 外部 `TextEditingController`：
/// 后者会在 `await showDialog` 返回时就 dispose 控制器，而对话框还在退场动画里
/// 用着它，真机上会直接抛 `_dependents.isEmpty` / "used after dispose" 把整个
/// App 变成红屏。
class RuleEditDialog extends StatefulWidget {
  const RuleEditDialog({
    super.key,
    this.initialType,
    this.initialPayload,
    this.initialTarget,
    this.initialNoResolve = false,
    required this.targets,
    this.otherBuiltins = const <String>[],
    required this.isNew,
    required this.handle,
    this.onDelete,
  });

  final String? initialType;
  final String? initialPayload;
  final String? initialTarget;
  final bool initialNoResolve;
  final List<String> targets;

  /// REJECT-DROP / PASS / COMPATIBLE / GLOBAL 这类高级内置：只在编辑规则时折叠成
  /// 「高级内置（不常用）」展示。
  final List<String> otherBuiltins;
  final bool isNew;

  /// 把当前草稿同步给外层，供「点遮罩自动保存」读取。
  final RuleDraftHandle handle;

  /// 编辑已有规则时的删除入口：返回 true 表示已经删掉，弹窗随之关闭。
  final Future<bool> Function()? onDelete;

  @override
  State<RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<RuleEditDialog> {
  late String _type;
  late String _target;
  late bool _noResolve;
  late final TextEditingController _payloadCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'DOMAIN-SUFFIX';
    // 新规则默认落到「默认」组：它带着全部节点 + DIRECT + REJECT。
    final preferred = widget.targets.contains(kDefaultGroupName)
        ? kDefaultGroupName
        : (widget.targets.isNotEmpty ? widget.targets.first : 'DIRECT');
    _target = widget.initialTarget ?? preferred;
    _noResolve = widget.initialNoResolve;
    _payloadCtrl = TextEditingController(text: widget.initialPayload ?? '');
    // 点遮罩时外层直接读 handle.draft；输入不重建本对话框，必须主动同步，
    // 否则填了内容再点外面仍会被当成「没填」。
    _payloadCtrl.addListener(_syncDraft);
  }

  void _syncDraft() {
    widget.handle.draft = _draft;
  }

  @override
  void dispose() {
    _payloadCtrl.removeListener(_syncDraft);
    _payloadCtrl.dispose();
    super.dispose();
  }

  bool get _needsPayload => !kTerminalRuleTypes.contains(_type);

  String get _payloadHint {
    switch (_type) {
      case 'DOMAIN':
      case 'DOMAIN-SUFFIX':
        return '例如 google.com';
      case 'DOMAIN-KEYWORD':
        return '例如 google';
      case 'DOMAIN-REGEX':
        return r'例如 ^ads?\..*';
      case 'GEOSITE':
        return '例如 cn';
      case 'GEOIP':
        return '例如 cn';
      case 'IP-CIDR':
      case 'IP-CIDR6':
      case 'SRC-IP-CIDR':
        return '例如 192.168.0.0/16';
      case 'DST-PORT':
      case 'SRC-PORT':
        return '例如 443 或 8000-8080';
      case 'PROCESS-NAME':
      case 'PROCESS-PATH':
        return '例如 com.android.chrome';
      case 'RULE-SET':
        return '规则集名称（rule-providers 里的键）';
      case 'NETWORK':
        return 'tcp 或 udp';
      case 'IN-TYPE':
        return '例如 inner / outer';
      case 'AND':
      case 'OR':
      case 'NOT':
        return '逻辑规则的括号表达式';
      default:
        return '匹配内容';
    }
  }

  RuleDraft? get _draft {
    final payload = _payloadCtrl.text.trim();
    if (_needsPayload && payload.isEmpty) return null;
    return RuleDraft(
      type: _type,
      payload: payload,
      target: _target,
      noResolve: _noResolve,
    );
  }

  bool _closing = false;

  /// 关闭弹窗：新建一律静默丢弃；编辑态合法才保存，非法丢弃并提示。
  void _dismiss() {
    if (_closing) return;
    _closing = true;
    if (widget.isNew) {
      Navigator.of(context).pop();
      return;
    }
    final draft = _draft;
    if (draft == null) {
      showToast(context, '内容无效，未保存');
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(draft);
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final deleted = await onDelete();
    if (!deleted || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  /// 新建规则的显式保存：内容不合法就留在窗口里提示，
  /// 不靠「点遮罩」隐式保存（那是编辑态的行为）。
  void _commitNew() {
    final draft = _draft;
    if (draft == null) {
      showToast(context, '请填写匹配内容');
      return;
    }
    _closing = true;
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    widget.handle.draft = _draft;
    final scheme = Theme.of(context).colorScheme;
    final types = <String>{
      ...kRuleTypes,
      if (!kRuleTypes.contains(_type)) _type,
    };
    return PopScope(
      // 系统返回与遮罩/右上 × 走同一套关闭语义：新建不拦退出。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: EditDialog(
        title: widget.isNew ? '新建规则' : '编辑规则',
        // 编辑态没有底部按钮（点遮罩/× 即保存）；新建态必须给显式「添加」，
        // 否则「允许随时退出」就变成「永远加不进来」。
        showFooter: widget.isNew,
        confirmLabel: '添加',
        onConfirm: widget.isNew ? _commitNew : null,
        onCancel: _dismiss,
        headerActions: !widget.isNew && widget.onDelete != null
            ? [
                IconButton(
                  tooltip: '删除这条规则',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: _delete,
                  color: scheme.error,
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ]
            : null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDropdown<String>(
              label: '类型',
              expand: true,
              value: _type,
              options: [for (final t in types) DropdownOption(t, t)],
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 12),
            if (_needsPayload)
              AppTextField(
                controller: _payloadCtrl,
                label: '匹配内容',
                hint: _payloadHint,
              ),
            if (_needsPayload) const SizedBox(height: 12),
            TargetSelectorField(
              label: '目标（策略 / 组）',
              value: _target,
              options: <String>{
                ...widget.targets,
                if (!widget.targets.contains(_target)) _target,
              }.toList(),
              otherOptions: widget.isNew
                  ? const <String>[]
                  : widget.otherBuiltins,
              onChanged: (v) => setState(() => _target = v),
            ),
            if (kNoResolveTypes.contains(_type))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('no-resolve'),
                subtitle: const Text('不解析域名（仅 GEOIP / IP-CIDR 生效）'),
                value: _noResolve,
                onChanged: (v) => setState(() => _noResolve = v),
              ),
          ],
        ),
      ),
    );
  }
}
