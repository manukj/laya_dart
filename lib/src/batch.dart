import 'dart:typed_data';

import 'config.dart';
import 'questions.dart';
import 'sequence.dart';
import 'serialization.dart';
import 'tokenizer_adapter.dart';

final class LayaBatch {
  LayaBatch._(
    this.questionIds,
    this.questions,
    this.sequences,
    this.sequenceLength,
    this.optionCount,
    this.inputIds,
    this.attentionMask,
    this.markerPositions,
    this.markerMask,
    this.questionTypes,
    this.inputTokens,
  );

  factory LayaBatch.build({
    required Object? state,
    required Map<String, LayaQuestion> questions,
    required LayaTokenizer tokenizer,
    required LayaConfig config,
  }) {
    if (questions.isEmpty) {
      throw ArgumentError('At least one question is required');
    }
    final special = SpecialTokenIds.fromTokenizer(tokenizer);
    final keys = referenceKeyOrder(questions.keys);
    final ordered = [for (final key in keys) questions[key]!];
    final sequences = <LayaSequence>[];
    for (var i = 0; i < keys.length; i++) {
      final sequence = buildSequence(
        tokenizer: tokenizer,
        specialIds: special,
        state: state,
        question: ordered[i],
        config: config,
      );
      if (sequence.markers.length != ordered[i].options.length) {
        throw ArgumentError(
          'Question "${keys[i]}": options do not fit in head_max_len=${config.headMaxLength} / max_len=${config.maxLength}',
        );
      }
      sequences.add(sequence);
    }
    final length = sequences
        .map((s) => s.ids.length)
        .reduce((a, b) => a > b ? a : b);
    final width = sequences
        .map((s) => s.markers.length)
        .reduce((a, b) => a > b ? a : b);
    final input = Int64List(keys.length * length)
      ..fillRange(0, keys.length * length, special.pad);
    final attention = Int64List(keys.length * length);
    final positions = Int64List(keys.length * width);
    final mask = List<bool>.filled(keys.length * width, false);
    final types = Int64List(keys.length);
    var tokens = 0;
    for (var row = 0; row < keys.length; row++) {
      final sequence = sequences[row];
      input.setRange(
        row * length,
        row * length + sequence.ids.length,
        sequence.ids,
      );
      attention.fillRange(row * length, row * length + sequence.ids.length, 1);
      positions.setRange(
        row * width,
        row * width + sequence.markers.length,
        sequence.markers,
      );
      mask.fillRange(row * width, row * width + sequence.markers.length, true);
      types[row] = ordered[row].type.index;
      tokens += sequence.ids.length;
    }
    return LayaBatch._(
      List.unmodifiable(keys),
      List.unmodifiable(ordered),
      List.unmodifiable(sequences),
      length,
      width,
      input.asUnmodifiableView(),
      attention.asUnmodifiableView(),
      positions.asUnmodifiableView(),
      List.unmodifiable(mask),
      types.asUnmodifiableView(),
      tokens,
    );
  }

  final List<String> questionIds;
  final List<LayaQuestion> questions;
  final List<LayaSequence> sequences;
  final int sequenceLength;
  final int optionCount;
  final Int64List inputIds;
  final Int64List attentionMask;
  final Int64List markerPositions;
  final List<bool> markerMask;
  final Int64List questionTypes;
  final int inputTokens;
  int get size => questionIds.length;

  Map<String, Object> toJson() => {
    'input_ids': {
      'type': 'int64',
      'shape': [size, sequenceLength],
      'data': inputIds.toList(),
    },
    'attention_mask': {
      'type': 'int64',
      'shape': [size, sequenceLength],
      'data': attentionMask.toList(),
    },
    'marker_pos': {
      'type': 'int64',
      'shape': [size, optionCount],
      'data': markerPositions.toList(),
    },
    'marker_mask': {
      'type': 'bool',
      'shape': [size, optionCount],
      'data': markerMask,
    },
    'qtype': {
      'type': 'int64',
      'shape': [size],
      'data': questionTypes.toList(),
    },
  };
}
