import '../model/profile.dart';
import 'config_ops.dart';

/// 规则目标候选。
///
/// 主列表顺序固定：自定义组（YAML 顺序，排除 DEFAULT / 自动选择）→ DEFAULT →
/// 自动选择 → DIRECT → REJECT。其余内置出站（REJECT-DROP / PASS / COMPATIBLE /
/// GLOBAL）单独放 [otherBuiltins]，由 UI 折叠展示，别混进主列表。
class RuleTargets {
  const RuleTargets({
    required this.primary,
    this.otherBuiltins = const <String>[],
  });

  final List<String> primary;
  final List<String> otherBuiltins;

  List<String> get all => <String>[...primary, ...otherBuiltins];
}

/// 生成规则目标候选；[preferred] 是当前值（编辑旧规则时可能已不在配置里）。
RuleTargets ruleTargetsFor(Profile profile, {String? preferred}) {
  final groups = <String>[for (final group in profile.groups) group.name];
  final primary = <String>[];
  void add(String name) {
    if (name.isNotEmpty && !primary.contains(name)) primary.add(name);
  }

  for (final name in groups) {
    if (name == kDefaultGroupName || name == kAutoGroupName) continue;
    add(name);
  }
  if (groups.contains(kDefaultGroupName)) add(kDefaultGroupName);
  if (groups.contains(kAutoGroupName)) add(kAutoGroupName);
  for (final name in Profile.systemPolicyTargets) {
    add(name);
  }
  final current = (preferred ?? '').trim();
  if (current.isNotEmpty) add(current);
  return RuleTargets(
    primary: primary,
    otherBuiltins: <String>[
      for (final name in Profile.builtinTargets)
        if (!primary.contains(name)) name,
    ],
  );
}
