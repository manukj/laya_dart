import 'questions.dart';

String temperatureBucket(QuestionType type, int count) {
  final bucket = count <= 2
      ? '2'
      : count <= 5
      ? '3-5'
      : count <= 10
      ? '6-10'
      : '11+';
  return '${type.name}:$bucket';
}

final class LayaConfig {
  LayaConfig({
    required this.maxLength,
    required this.headMaxLength,
    List<double> temperatures = const [1, 1, 1],
    Map<String, double> temperaturesByOptions = const {},
  }) : temperatures = List.unmodifiable(temperatures),
       temperaturesByOptions = Map.unmodifiable(temperaturesByOptions) {
    if (maxLength < 4 || headMaxLength < 1 || headMaxLength > maxLength) {
      throw const FormatException(
        'Laya limits must satisfy max_len >= 4 and 1 <= head_max_len <= max_len',
      );
    }
    if (temperatures.length > 3 ||
        [
          ...temperatures,
          ...temperaturesByOptions.values,
        ].any((t) => !t.isFinite || t <= 0)) {
      throw const FormatException(
        'Laya temperatures must be finite and positive (at most three type values)',
      );
    }
  }

  factory LayaConfig.fromJson(Map<String, Object?> json) {
    final max = json['max_len'];
    final head = json['head_max_len'];
    final temperatures = json['temperature'];
    final buckets = json['temperature_by_options'];
    if (max is! int ||
        head is! int ||
        temperatures is! List ||
        temperatures.any((v) => v is! num) ||
        buckets is! Map ||
        buckets.keys.any((v) => v is! String) ||
        buckets.values.any((v) => v is! num)) {
      throw const FormatException(
        'Invalid laya_config.json: expected integer limits, temperature list and temperature_by_options map',
      );
    }
    return LayaConfig(
      maxLength: max,
      headMaxLength: head,
      temperatures: temperatures.cast<num>().map((v) => v.toDouble()).toList(),
      temperaturesByOptions: {
        for (final entry in buckets.entries)
          entry.key as String: (entry.value as num).toDouble(),
      },
    );
  }

  final int maxLength;
  final int headMaxLength;
  final List<double> temperatures;
  final Map<String, double> temperaturesByOptions;

  double temperatureFor(QuestionType type, int count) =>
      temperaturesByOptions[temperatureBucket(type, count)] ??
      (type.index < temperatures.length ? temperatures[type.index] : 1);
}
