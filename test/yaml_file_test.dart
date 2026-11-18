import 'dart:convert';
import 'dart:typed_data';

import 'package:clashdeck/core/io/yaml_file.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

PickedYamlFile _file(String name, {String? text, List<int>? raw}) =>
    PickedYamlFile(
      name: name,
      bytes: raw != null ? Uint8List.fromList(raw) : _bytes(text ?? ''),
    );

void main() {
  group('扩展名', () {
    test('yaml / yml / txt 忽略大小写', () {
      expect(hasYamlFileExtension('demo.yaml'), isTrue);
      expect(hasYamlFileExtension('DEMO.YML'), isTrue);
      expect(hasYamlFileExtension('订阅.txt'), isTrue);
      expect(hasYamlFileExtension('/sdcard/Download/a.yaml'), isTrue);
    });

    test('其它扩展名、无扩展名、隐藏文件都不收', () {
      expect(hasYamlFileExtension('demo.json'), isFalse);
      expect(hasYamlFileExtension('demo'), isFalse);
      expect(hasYamlFileExtension('.yaml'), isFalse);
      expect(hasYamlFileExtension('demo.yaml.bak'), isFalse);
    });
  });

  group('配置名', () {
    test('去掉目录与扩展名', () {
      expect(configNameFromFileName('/sdcard/x/demo.yaml'), 'demo');
      expect(configNameFromFileName('a.b.yml'), 'a.b');
      expect(configNameFromFileName('  订阅  .txt'), '订阅');
    });

    test('空名字回落到「导入的配置」', () {
      expect(configNameFromFileName('.yaml'), '导入的配置');
      expect(configNameFromFileName('   '), '导入的配置');
    });
  });

  group('decodeYamlFile', () {
    test('正常 UTF-8，去掉 BOM', () {
      final text = decodeYamlFile(_file('a.yaml', text: '\uFEFFproxies: []\n'));
      expect(text, 'proxies: []\n');
    });

    test('扩展名不支持', () {
      expect(
        () => decodeYamlFile(_file('a.json', text: '{}')),
        throwsA(
          isA<YamlFileException>().having(
            (e) => e.message,
            'message',
            contains('只支持'),
          ),
        ),
      );
    });

    test('超过 2MB 直接拒绝', () {
      final big = Uint8List(maxYamlFileBytes + 1);
      expect(
        () => decodeYamlFile(PickedYamlFile(name: 'big.yaml', bytes: big)),
        throwsA(
          isA<YamlFileException>().having(
            (e) => e.message,
            'message',
            contains('2MB'),
          ),
        ),
      );
    });

    test('不是 UTF-8', () {
      expect(
        () => decodeYamlFile(_file('a.yaml', raw: <int>[0xff, 0xfe, 0x00])),
        throwsA(
          isA<YamlFileException>().having(
            (e) => e.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );
    });

    test('空文件', () {
      expect(
        () => decodeYamlFile(_file('a.yaml', text: '  \n ')),
        throwsA(
          isA<YamlFileException>().having(
            (e) => e.message,
            'message',
            contains('空'),
          ),
        ),
      );
    });
  });
}
