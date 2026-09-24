import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:laya_dart/laya_dart.dart';

const _modelDir = String.fromEnvironment('LAYA_MODEL_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'queues overlapping requests and rejects new work after close',
    (tester) async {
      final laya = await Laya.load(_modelDir);
      addTearDown(laya.close);
      final questions = {
        'department': LayaQuestion.choice(
          instructions: 'Which team should handle this message?',
          criteria: {
            'billing': 'payments and refunds',
            'technical': 'bugs and outages',
            'other': 'anything else',
          },
        ),
      };

      final first = laya.predictAsync(
        'Please refund my duplicate charge.',
        questions,
      );
      final second = laya.predictAsync(
        'The dashboard returns a 500 error.',
        questions,
      );
      final results = await Future.wait([first, second]);

      expect(results, hasLength(2));
      expect(results[0]['answers'], isA<Map<String, Object>>());
      expect(results[1]['answers'], isA<Map<String, Object>>());

      await laya.close();
      await expectLater(
        laya.predictAsync('ignored after close', questions),
        throwsStateError,
      );
    },
    skip: _modelDir.isEmpty,
  );

  testWidgets('repeats inference after warm-up', (tester) async {
    final laya = await Laya.load(_modelDir);
    addTearDown(laya.close);
    final questions = {
      'refund': LayaQuestion.noul(
        instructions: 'Does the message request a refund?',
      ),
    };

    for (var i = 0; i < 10; i++) {
      final result = await laya.predictAsync('I need a refund.', questions);
      expect(result['answers'], isA<Map<String, Object>>());
    }
  }, skip: _modelDir.isEmpty);
}
