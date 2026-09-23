import 'serialization.dart';

enum QuestionType { choice, score, noul }

/// A validated, immutable question in the upstream Laya request format.
final class LayaQuestion {
  LayaQuestion._(
    this.type,
    this.instructions,
    this.options,
    this.labels,
    this.levels,
  );

  factory LayaQuestion.fromJson(Map<String, Object?> json) {
    final type = switch (json['type']) {
      'choice' => QuestionType.choice,
      'score' => QuestionType.score,
      'noul' => QuestionType.noul,
      _ => throw ArgumentError('Question type must be choice, score, or noul'),
    };
    final instruction = json['instructions'];
    if (instruction is! String && instruction is! Map && instruction is! List) {
      throw ArgumentError(
        'Question instructions must be a string or JSON object',
      );
    }
    final instructions = instruction is String
        ? instruction
        : referenceJson(instruction, spaced: false);
    final criteria = json['criteria'];
    final labels = <String>[];
    final options = <String>[];
    final levels = <String>[];
    if (type == QuestionType.choice) {
      final Map<String, String?> choices;
      if (criteria is List && criteria.every((v) => v is String)) {
        choices = {for (final item in criteria) item as String: null};
      } else if (criteria is Map &&
          criteria.keys.every((k) => k is String) &&
          criteria.values.every((v) => v == null || v is String)) {
        choices = Map<String, String?>.from(criteria);
      } else {
        throw ArgumentError(
          'Choice criteria must be a string list or label/description map',
        );
      }
      labels.addAll(referenceKeyOrder(choices.keys));
      options.addAll(
        labels.map((label) {
          final description = choices[label];
          return description == null || description.isEmpty
              ? label
              : '$label: $description';
        }),
      );
    } else if (type == QuestionType.score) {
      if (criteria is! List || criteria.any((v) => v is! String)) {
        throw ArgumentError('Score criteria must be an ordered string list');
      }
      levels.addAll(criteria.cast<String>());
      for (var i = 0; i < levels.length; i++) {
        labels.add('$i');
        options.add('level $i: ${levels[i]}');
      }
    } else {
      if (criteria != null &&
          (criteria is! Map ||
              criteria.keys.any((k) => k != 'true' && k != 'false') ||
              criteria.values.any((v) => v is! String))) {
        throw ArgumentError(
          'Noul criteria must contain only true/false string descriptions',
        );
      }
      final descriptions = criteria == null
          ? <String, String>{}
          : Map<String, String>.from(criteria as Map);
      String description(String key, String fallback) {
        final value = descriptions[key];
        return value == null || value.isEmpty ? fallback : value;
      }

      labels.addAll(['false', 'true']);
      options.addAll([
        'false: ${description('false', 'no, the statement does not hold')}',
        'true: ${description('true', 'yes, the statement holds')}',
      ]);
    }
    if (options.isEmpty) {
      throw ArgumentError('Question criteria must contain at least one option');
    }
    return LayaQuestion._(
      type,
      instructions,
      List.unmodifiable(options),
      List.unmodifiable(labels),
      List.unmodifiable(levels),
    );
  }

  factory LayaQuestion.choice({
    required Object instructions,
    required Object criteria,
  }) => LayaQuestion.fromJson({
    'type': 'choice',
    'instructions': instructions,
    'criteria': criteria,
  });
  factory LayaQuestion.score({
    required Object instructions,
    required List<String> criteria,
  }) => LayaQuestion.fromJson({
    'type': 'score',
    'instructions': instructions,
    'criteria': criteria,
  });
  factory LayaQuestion.noul({
    required Object instructions,
    Map<String, String>? criteria,
  }) => LayaQuestion.fromJson({
    'type': 'noul',
    'instructions': instructions,
    'criteria': criteria,
  });

  final QuestionType type;
  final String instructions;
  final List<String> options;
  final List<String> labels;
  final List<String> levels;
}
