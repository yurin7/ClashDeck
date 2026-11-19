import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/edit/save_restart.dart';

void main() {
  test('当前配置 + 内核在跑：保存后自动重启', () {
    expect(
      shouldRestartAfterSave(isActiveProfile: true, coreActive: true),
      isTrue,
    );
  });

  test('当前配置 + 内核没跑：只保存，不重启', () {
    expect(
      shouldRestartAfterSave(isActiveProfile: true, coreActive: false),
      isFalse,
    );
  });

  test('非当前配置：即使内核在跑也绝不重启', () {
    expect(
      shouldRestartAfterSave(isActiveProfile: false, coreActive: true),
      isFalse,
    );
  });

  test('非当前配置 + 内核没跑：不重启', () {
    expect(
      shouldRestartAfterSave(isActiveProfile: false, coreActive: false),
      isFalse,
    );
  });
}
