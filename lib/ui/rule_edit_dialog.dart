import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/rule_types.dart';
import 'dropdown.dart';
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
    required this.isNew,
  });

  final String? initialType;
  final String? initialPayload;
  final String? initialTarget;
  final bool initialNoResolve;
  final List<String> targets;
  final bool isNew;

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
  }

  @override
  void dispose() {
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

  void _submit() {
    final payload = _payloadCtrl.text.trim();
    if (_needsPayload && payload.isEmpty) {
      showToast(context, '请填写匹配内容');
      return;
    }
    Navigator.of(context).pop(
      RuleDraft(
        type: _type,
        payload: payload,
        target: _target,
        noResolve: _noResolve,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final types = <String>{
      ...kRuleTypes,
      if (!kRuleTypes.contains(_type)) _type,
    };
    return AlertDialog(
      title: Text(widget.isNew ? '新建规则' : '编辑规则'),
      content: SingleChildScrollView(
        child: Column(
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
              TextField(
                controller: _payloadCtrl,
                autofocus: false,
                decoration: InputDecoration(
                  labelText: '匹配内容',
                  hintText: _payloadHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_needsPayload) const SizedBox(height: 12),
            AppDropdown<String>(
              label: '目标（策略 / 组）',
              expand: true,
              value: _target,
              options: [
                for (final t in <String>{
                  ...widget.targets,
                  if (!widget.targets.contains(_target)) _target,
                })
                  DropdownOption(t, t),
              ],
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
      actions: [
        if (!widget.isNew)
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [Icon(Icons.delete_outline, size: 18), Text('删除')],
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}
