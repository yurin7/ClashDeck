import 'dart:io';

import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

const base = r'''
proxies:
  - name: A
    type: vless
    server: a.example.com
    port: 443
    uuid: u
proxy-groups:
  - name: G
    type: select
    proxies: [A]
rules:
  - MATCH,G
''';

void main() {
  test('编辑可撤销/可重做', () {
    final s = EditorState.fromText(base);
    expect(s.dirty, isFalse);
    expect(s.canUndo, isFalse);

    expect(s.addProxy({'name': 'B', 'type': 'vless', 'server': 'b', 'port': 1, 'uuid': 'u'}), isTrue);
    expect(s.dirty, isTrue);
    expect(s.canUndo, isTrue);
    expect(s.profile.proxies.map((e) => e.name), ['A', 'B']);

    s.undo();
    expect(s.profile.proxies.map((e) => e.name), ['A']);
    expect(s.dirty, isFalse);
    expect(s.canRedo, isTrue);

    s.redo();
    expect(s.profile.proxies.map((e) => e.name), ['A', 'B']);
  });

  test('失败的操作不改变状态、不留撤销记录、记录错误', () {
    final s = EditorState.fromText(base);
    final before = s.doc.text;
    expect(s.addProxy({'name': 'A', 'type': 'vless'}), isFalse); // 重名
    expect(s.doc.text, before);
    expect(s.canUndo, isFalse);
    expect(s.lastError, contains('已存在'));
  });

  test('新操作会清空重做栈', () {
    final s = EditorState.fromText(base);
    s.addProxy({'name': 'B', 'type': 'vless', 'server': 'b', 'port': 1, 'uuid': 'u'});
    s.undo();
    expect(s.canRedo, isTrue);
    s.addProxy({'name': 'C', 'type': 'vless', 'server': 'c', 'port': 1, 'uuid': 'u'});
    expect(s.canRedo, isFalse);
  });

  test('撤销栈有上限', () {
    final s = EditorState.fromText(base, historyLimit: 2);
    for (final n in ['1', '2', '3']) {
      s.addProxy({'name': n, 'type': 'vless', 'server': n, 'port': 1, 'uuid': 'u'});
    }
    s.undo();
    s.undo();
    expect(s.canUndo, isFalse);
  });

  test('保存后脏标记清除，并写入仓库', () async {
    final tmp = await Directory.systemTemp.createTemp('clashdeck_test');
    addTearDown(() => tmp.delete(recursive: true));
    final store = ProfileStore(tmp);

    final s = EditorState.fromText(base);
    s.addProxy({'name': 'B', 'type': 'vless', 'server': 'b', 'port': 1, 'uuid': 'u'});
    await s.saveAs(store, '测试配置');
    expect(s.dirty, isFalse);
    expect(s.fileName, '测试配置.yaml');

    final list = await store.list();
    expect(list.single.name, '测试配置');
    expect(await store.read('测试配置.yaml'), contains('name: B'));
  });

  test('校验报告随编辑刷新', () {
    final s = EditorState.fromText('rules:\n  - DOMAIN,a.com,DIRECT\n');
    expect(s.report.issues.map((e) => e.code), contains('no-terminal-rule'));
    s.addRule('MATCH,DIRECT');
    expect(s.report.issues.map((e) => e.code), isNot(contains('no-terminal-rule')));
  });

  test('replaceText 重置文档并保留撤销', () {
    final s = EditorState.fromText(base);
    s.replaceText('mode: global\n');
    expect(s.profile.mode, 'global');
    expect(s.canUndo, isTrue);
    s.undo();
    expect(s.profile.mode, 'rule');
  });

  test('文件名净化：非法字符替换、重名加序号', () async {
    final tmp = await Directory.systemTemp.createTemp('clashdeck_test2');
    addTearDown(() => tmp.delete(recursive: true));
    final store = ProfileStore(tmp);
    expect(ProfileStore.sanitizeName('a/b:c*'), 'a_b_c_');
    final a = await store.create('同一个名字', 'a: 1\n');
    final b = await store.create('同一个名字', 'a: 2\n');
    expect(a.fileName, '同一个名字.yaml');
    expect(b.fileName, '同一个名字-2.yaml');
    expect((await store.list()).length, 2);
  });
}
