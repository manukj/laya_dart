// Ported from Receptron Laya, MIT; see THIRD_PARTY_NOTICES.md.
import 'dart:math' as math;

import 'config.dart';
import 'questions.dart';
import 'serialization.dart';
import 'tokenizer_adapter.dart';

final class LayaSequence {
  LayaSequence({required List<int> ids, required List<int> markers})
    : ids = List.unmodifiable(ids),
      markers = List.unmodifiable(markers);
  final List<int> ids;
  final List<int> markers;
}

LayaSequence buildSequence({
  required LayaTokenizer tokenizer,
  required SpecialTokenIds specialIds,
  required Object? state,
  required LayaQuestion question,
  required LayaConfig config,
}) {
  String scrub(String text) => text.replaceAll(specialIds.maskToken, ' ');
  List<int> encode(String text) {
    final ids = tokenizer.encode(text);
    if (ids.any((id) => id < 0)) {
      throw StateError('Tokenizer returned a negative token ID');
    }
    return ids;
  }

  var head = encode(
    '${question.type.name} question: ${scrub(question.instructions)}',
  );
  var options = question.options
      .map((o) => [specialIds.mask, ...encode(' ${scrub(o)}').take(48)])
      .toList();
  int total() => options.fold(0, (sum, option) => sum + option.length);
  var budget = config.headMaxLength - total();
  if (budget < 16) {
    final per = math.max(
      4,
      ((config.headMaxLength - 16) / math.max(1, options.length)).floor(),
    );
    options = options.map((option) => option.take(per).toList()).toList();
    budget = config.headMaxLength - total();
  }
  head = head.take(math.max(8, budget)).toList();
  final ids = [specialIds.cls, ...head, specialIds.sep];
  final markers = <int>[];
  for (final option in options) {
    markers.add(ids.length);
    ids.addAll(option);
  }
  ids.add(specialIds.sep);
  final room = math.max(0, config.maxLength - ids.length - 1);
  ids.addAll(encode(scrub(serializeState(state))).take(room));
  ids.add(specialIds.sep);
  return LayaSequence(
    ids: ids.take(config.maxLength).toList(),
    markers: markers.where((m) => m < config.maxLength).toList(),
  );
}
