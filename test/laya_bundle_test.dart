import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laya_dart/laya_dart.dart';

void main() {
  test('rejects a bundle with no tokenizer directory', () async {
    final directory = await Directory.systemTemp.createTemp('laya-missing-tokenizer-');
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      Laya.load(directory.path),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a bundle with no config file', () async {
    final directory = await Directory.systemTemp.createTemp('laya-missing-config-');
    addTearDown(() => directory.delete(recursive: true));
    await Directory('${directory.path}/tokenizer').create();

    await expectLater(
      Laya.load(directory.path),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a bundle with no model file', () async {
    final directory = await Directory.systemTemp.createTemp('laya-missing-model-');
    addTearDown(() => directory.delete(recursive: true));
    final tokenizer = Directory('${directory.path}/tokenizer');
    await tokenizer.create();
    await File('${tokenizer.path}/tokenizer.json').writeAsString('{}');
    await File('${tokenizer.path}/tokenizer_config.json').writeAsString('{}');
    await File('${directory.path}/laya_config.json').writeAsString('{}');

    await expectLater(
      Laya.load(directory.path),
      throwsA(isA<ArgumentError>()),
    );
  });
}
