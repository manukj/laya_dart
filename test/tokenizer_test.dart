import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:laya_dart/laya_dart.dart';

void main() {
  late ByteLevelBpeTokenizer tokenizer;
  final fixtures =
      jsonDecode(File('test/fixtures/tokenizer_cases.json').readAsStringSync())
          as Map;
  setUpAll(() async {
    tokenizer = await ByteLevelBpeTokenizer.fromDirectory(
      'test/fixtures/tokenizer',
    );
  });
  test('E3: special IDs match reference lookups', () {
    for (final entry in (fixtures['specialIds'] as Map).entries) {
      expect(tokenizer.tokenToId(entry.key as String), entry.value);
    }
  });
  for (final (index, item) in (fixtures['cases'] as List).indexed) {
    test('E4–E8: exact token IDs for corpus item $index', () {
      expect(
        tokenizer.encode(item['text'] as String),
        item['ids'],
        reason: jsonEncode(item['text']),
      );
    });
  }
  test('E2: unsupported pipelines fail clearly', () {
    final data =
        jsonDecode(
              File('test/fixtures/tokenizer/tokenizer.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final config =
        jsonDecode(
              File(
                'test/fixtures/tokenizer/tokenizer_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    data['normalizer'] = {'type': 'NFKC'};
    expect(
      () => ByteLevelBpeTokenizer.fromJson(data, config),
      throwsFormatException,
    );
  });
}
