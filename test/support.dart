import 'dart:convert';
import 'dart:io';
import 'package:laya_dart/laya_dart.dart';

final class FixtureTokenizer implements LayaTokenizer {
  final encodedTexts = <String>[];
  @override
  List<int> encode(String text) {
    encodedTexts.add(text);
    return text.runes.map((r) => r + 100).toList();
  }

  @override
  int? tokenToId(String token) =>
      {'[CLS]': 1, '[SEP]': 2, '[MASK]': 3, '[PAD]': 17}[token];
}

List<Map<String, dynamic>> fixtureCases() =>
    (jsonDecode(
              File('test/fixtures/model_free_cases.json').readAsStringSync(),
            )['cases']
            as List)
        .cast<Map<String, dynamic>>();

Map<String, LayaQuestion> fixtureQuestions(Map<String, dynamic> fixture) =>
    (fixture['questions'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(
        key,
        LayaQuestion.fromJson(Map<String, Object?>.from(value as Map)),
      ),
    );

LayaConfig fixtureConfig(Map<String, dynamic> fixture) =>
    LayaConfig.fromJson(Map<String, Object?>.from(fixture['config'] as Map));

LayaBatch fixtureBatch(Map<String, dynamic> fixture) => LayaBatch.build(
  state: fixture['state'],
  questions: fixtureQuestions(fixture),
  tokenizer: FixtureTokenizer(),
  config: fixtureConfig(fixture),
);
