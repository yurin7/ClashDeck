import 'package:material_ui/material_ui.dart';

import 'rules_tab.dart' show kRuleTypes, kNoResolveTypes, kTerminalRuleTypes;

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
  late final TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? 'DOMAIN-SUFFIX';
    _target =
        widget.initialTarget ??
        (widget.targets.isNotEmpty ? widget.targets.first : 'DIRECT');
    _noResolve = widget.initialNoResolve;
    _payloadCtrl = TextEditingController(text: widget.initialPayload ?? '');
    _customCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _payloadCtrl.dispose();
    _customCtrl.dispose();
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
    final custom = _customCtrl.text.trim();
    if (_needsPayload && payload.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写匹配内容')));
      return;
    }
    Navigator.of(context).pop(
      RuleDraft(
        type: _type,
        payload: payload,
        target: custom.isEmpty ? _target : custom,
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
            DropdownButtonFormField<String>(
              key: ValueKey('rule-type-$_type'),
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _type = v);
              },
            ),
            const SizedBox(height: 12),
            if (_needsPayload)
              TextField(
                controller: _payloadCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '匹配内容',
                  hintText: _payloadHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_needsPayload) const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('rule-target-$_target'),
              initialValue: _target,
              decoration: const InputDecoration(
                labelText: '目标（策略 / 组）',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final t in <String>{
                  ...widget.targets,
                  if (!widget.targets.contains(_target)) _target,
                })
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _target = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customCtrl,
              decoration: const InputDecoration(
                labelText: '目标不在列表里？手动填写',
                hintText: '例如 DOH 或自定义组名',
                border: OutlineInputBorder(),
              ),
            ),
            if (kNoResolveTypes.contains(_type))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('no-resolve（不解析域名）'),
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
            child: const Text('删除'),
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
