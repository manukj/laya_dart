import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:laya_dart/laya_dart.dart';
import 'support.dart';

void main() {
  for (final fixture in fixtureCases()) {
    group(fixture['name'] as String, () {
      test('F1–F3: serialized text matches pinned TypeScript', () {
        expect(serializeState(fixture['state']), fixture['serializedState']);
      });
      test('F4–F10: options, encoded pieces, IDs and markers match', () {
        final questions = fixtureQuestions(fixture);
        for (final expected in fixture['sequences'] as List) {
          final q = questions[expected['qid']]!;
          final tokenizer = FixtureTokenizer();
          final sequence = buildSequence(
            tokenizer: tokenizer,
            specialIds: SpecialTokenIds.fromTokenizer(tokenizer),
            state: fixture['state'],
            question: q,
            config: fixtureConfig(fixture),
          );
          expect(q.options, expected['options']);
          expect(tokenizer.encodedTexts, expected['encodedTexts']);
          expect(sequence.ids, expected['ids']);
          expect(sequence.markers, expected['markers']);
        }
      });
      if (fixture.containsKey('error')) {
        test('F9: reject options lost through truncation', () {
          expect(() => fixtureBatch(fixture), throwsArgumentError);
        });
      } else {
        test('G1–G6: every element, type and shape matches', () {
          final batch = fixtureBatch(fixture);
          expect(batch.toJson(), fixture['tensors']);
          expect(batch.inputIds, isA<Int64List>());
          expect(batch.attentionMask, isA<Int64List>());
          expect(batch.markerPositions, isA<Int64List>());
          expect(batch.questionTypes, isA<Int64List>());
          expect(batch.markerMask, isA<List<bool>>());
        });
        test('H2–H10: complete decoded result matches upstream', () {
          final outputs = fixture['rawOutputs'] as Map;
          final actual = decodeOutputs(
            batch: fixtureBatch(fixture),
            config: fixtureConfig(fixture),
            logits: (outputs['logits']['data'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList(),
            actionProbabilities: (outputs['act_probs']['data'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList(),
          );
          expect(actual, fixture['result']);
        });
      }
    });
  }
}
