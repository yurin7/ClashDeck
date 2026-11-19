import 'package:flutter_test/flutter_test.dart';

import '../tool/release_notes.dart';

const _fixture = '''
# 更新日志

## [0.3.4] - 未发布

### Added

- 自动测速一轮。
- 延迟胶囊。

### Fixed

- 测速完成 toast 数字为空。

### Tests

- `test/proxy_board_delay_test.dart`：toast 数量。

## [0.3.3] - 2026-11-19

### Changed

- 右缘手势带打开抽屉。

### Fixed

- 诊断面板读错 YAML key。

## [0.3.2] - 2026-11-19

### Added

- 右侧 80% 抽屉。
''';

void main() {
  test('按版本抽段：只取请求版本的内容', () {
    final notes = parseChangelog(_fixture, version: '0.3.4');
    expect(notes.matchedVersion, '0.3.4');
    expect(notes.fallback, isFalse);
    expect(notes.sections['新增'], hasLength(2));
    expect(notes.sections['修复'], hasLength(1));
    expect(notes.sections['测试与构建'], hasLength(1));
    expect(notes.sections['改进'], isNull);
    expect(notes.sections['新增']!.join('\n'), isNot(contains('右侧 80% 抽屉')));
  });

  test('分类按固定顺序渲染，空分类不输出', () {
    final notes = parseChangelog(_fixture, version: '0.3.4');
    final text = renderReleaseNotes(notes, sha: 'abc1234');
    expect(text, startsWith('## 更新内容（v0.3.4）'));
    expect(text, contains('> 本次发布：正式版 · 版本 0.3.4 · 提交 abc1234'));
    expect(text.indexOf('### 新增'), lessThan(text.indexOf('### 修复')));
    expect(text.indexOf('### 修复'), lessThan(text.indexOf('### 测试与构建')));
    expect(text, isNot(contains('### 改进')));
    expect(text, isNot(contains('### 移除')));
    expect(text, contains('- 自动测速一轮。'));
  });

  test('找不到版本时回退最新段并带提示', () {
    final notes = parseChangelog(_fixture, version: '9.9.9');
    expect(notes.fallback, isTrue);
    expect(notes.matchedVersion, '0.3.4');
    final text = renderReleaseNotes(notes, sha: 'abc1234');
    expect(text, contains('> 未找到该版本段落，展示最近变更'));
  });

  test('优先回退 Unreleased 段', () {
    final withUnreleased = '''
## [9.9.9] - 未发布

### Fixed

- 未来修复。

## [0.3.4] - 未发布

### Added

- 老内容。
''';
    final notes = parseChangelog(withUnreleased, version: '1.0.0');
    expect(notes.matchedVersion, '9.9.9');
    expect(notes.sections['修复'], isNotNull);
  });

  test('开发版渲染最近提交；无提交时只留标题', () {
    final text = renderDevNotes(
      version: '0.0.123',
      sha: 'abc1234',
      commits: const ['- feat: a (aaa1111)', '- fix: b (bbb2222)'],
    );
    expect(text, startsWith('## 最近提交（开发版 0.0.123 · abc1234）'));
    expect(text, contains('- feat: a (aaa1111)'));
    final empty = renderDevNotes(
      version: '0.0.123',
      sha: 'abc1234',
      commits: const [],
    );
    expect(empty.trimRight(), '## 最近提交（开发版 0.0.123 · abc1234）');
  });

  test('带后缀的英文子标题按前缀归类', () {
    const source = '''
## [0.3.4]

### Tests / CI

- 自检更新。

### Fixes (Android)

- 磁贴状态。
''';
    final notes = parseChangelog(source, version: '0.3.4');
    expect(notes.sections['测试与构建'], hasLength(1));
    expect(notes.sections['修复'], hasLength(1));
  });
}
