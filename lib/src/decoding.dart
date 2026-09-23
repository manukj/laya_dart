// Ported from Receptron Laya, MIT; see THIRD_PARTY_NOTICES.md.
import 'dart:math' as math;

import 'batch.dart';
import 'config.dart';
import 'questions.dart';

List<double> softmax(List<double> logits) {
  if (logits.isEmpty || logits.any((v) => !v.isFinite)) {
    throw ArgumentError('Softmax needs finite, nonempty logits');
  }
  final maximum = logits.reduce(math.max);
  final exponents = logits.map((v) => math.exp(v - maximum)).toList();
  final sum = exponents.fold(0.0, (a, b) => a + b);
  return exponents.map((v) => v / sum).toList();
}

double confidenceFromProbabilities(List<double> probabilities) {
  if (probabilities.isEmpty ||
      probabilities.any((p) => !p.isFinite || p < 0 || p > 1) ||
      (probabilities.fold(0.0, (a, b) => a + b) - 1).abs() > 1e-6) {
    throw ArgumentError('Expected a normalized probability distribution');
  }
  if (probabilities.length < 2) return 1;
  var entropy = 0.0;
  for (final p in probabilities) {
    entropy -= p * math.log(math.max(p, 1e-12));
  }
  return 1 - entropy / math.log(probabilities.length);
}

double _round4(double value) => (value * 1e4 + 0.5).floor() / 1e4;

/// Decode flattened [B,K] logits and [B,2] action probabilities.
/// Padded logits are never included in the answer distribution.
Map<String, Object> decodeOutputs({
  required LayaBatch batch,
  required LayaConfig config,
  required List<double> logits,
  required List<double> actionProbabilities,
}) {
  if (logits.length != batch.size * batch.optionCount ||
      actionProbabilities.length != batch.size * 2) {
    throw ArgumentError(
      'Expected logits [${batch.size}, ${batch.optionCount}] and act_probs [${batch.size}, 2]',
    );
  }
  if (actionProbabilities.any((p) => !p.isFinite || p < 0 || p > 1)) {
    throw ArgumentError('act_probs must contain finite probabilities');
  }
  final answers = <String, Object>{};
  for (var row = 0; row < batch.size; row++) {
    final q = batch.questions[row];
    final count = q.options.length;
    final temperature = config.temperatureFor(q.type, count);
    final probabilities = softmax(
      logits
          .sublist(row * batch.optionCount, row * batch.optionCount + count)
          .map((v) => v / temperature)
          .toList(),
    );
    final answer = <String, Object>{'type': q.type.name};
    switch (q.type) {
      case QuestionType.choice:
        final best = probabilities.indexOf(probabilities.reduce(math.max));
        answer['choice'] = q.labels[best];
        answer['probabilities'] = {
          for (var i = 0; i < count; i++)
            q.labels[i]: _round4(probabilities[i]),
        };
        answer['confidence'] = _round4(
          confidenceFromProbabilities(probabilities),
        );
      case QuestionType.score:
        var score = 0.0;
        for (var i = 0; i < count; i++) {
          score += i * probabilities[i];
        }
        answer['score'] = _round4(score);
        answer['legend'] = {for (var i = 0; i < count; i++) '$i': q.levels[i]};
        answer['probabilities'] = {
          for (var i = 0; i < count; i++) '$i': _round4(probabilities[i]),
        };
        answer['confidence'] = _round4(
          confidenceFromProbabilities(probabilities),
        );
      case QuestionType.noul:
        answer['noul'] = _round4(probabilities[1]);
    }
    answer['rl_agent'] = {'act_probability': actionProbabilities[row * 2]};
    answers[batch.questionIds[row]] = answer;
  }
  return {
    'model': 'laya',
    'answers': answers,
    'usage': {'input_tokens': batch.inputTokens, 'output_tokens': 0},
  };
}
