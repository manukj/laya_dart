import 'dart:convert';

/// JavaScript Object.keys order, including its special ordering of index keys.
List<String> referenceKeyOrder(Iterable<String> keys) {
  final indices = <String>[];
  final rest = <String>[];
  for (final key in keys) {
    final number = int.tryParse(key);
    if (number != null &&
        number >= 0 &&
        number < 4294967295 &&
        '$number' == key) {
      indices.add(key);
    } else {
      rest.add(key);
    }
  }
  indices.sort((a, b) => int.parse(a).compareTo(int.parse(b)));
  return [...indices, ...rest];
}

String _number(num value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'state', 'JSON numbers must be finite');
  }
  if (value is int && value.abs() > 9007199254740991) {
    throw ArgumentError.value(
      value,
      'state',
      'Integer exceeds JavaScript safe precision; use a string',
    );
  }
  if (value == 0) return '0';
  var text = value.toDouble().toString();
  final parts = text.toLowerCase().split('e');
  var mantissa = parts[0];
  if (mantissa.endsWith('.0')) {
    mantissa = mantissa.substring(0, mantissa.length - 2);
  }
  if (parts.length == 1) return mantissa;
  final exponent = int.parse(parts[1]);
  if (exponent < -6 || exponent >= 21) {
    return '${mantissa}e${exponent >= 0 ? '+' : ''}$exponent';
  }
  final negative = mantissa.startsWith('-');
  if (negative) mantissa = mantissa.substring(1);
  final dot = mantissa.indexOf('.');
  final point = (dot < 0 ? mantissa.length : dot) + exponent;
  final digits = mantissa.replaceAll('.', '');
  if (point <= 0) {
    text = '0.${'0' * -point}$digits';
  } else if (point >= digits.length) {
    text = digits + '0' * (point - digits.length);
  } else {
    text = '${digits.substring(0, point)}.${digits.substring(point)}';
  }
  return '${negative ? '-' : ''}$text';
}

/// The pinned TypeScript serializer: Unicode JSON with Python-style spacing.
/// Numeric object keys follow JavaScript order, not Dart insertion order.
String referenceJson(Object? value, {bool spaced = true}) {
  final ancestors = <Object>{};
  String encode(Object? current) {
    if (current == null) return 'null';
    if (current is String) return jsonEncode(current);
    if (current is bool) return current ? 'true' : 'false';
    if (current is num) return _number(current);
    if (current is! List && current is! Map) {
      throw ArgumentError.value(
        current,
        'state',
        'Expected a JSON-compatible value',
      );
    }
    if (!ancestors.add(current)) throw ArgumentError('Cyclic JSON value');
    try {
      final separator = spaced ? ', ' : ',';
      if (current is List) return '[${current.map(encode).join(separator)}]';
      final map = current as Map;
      if (map.keys.any((key) => key is! String)) {
        throw ArgumentError('JSON object keys must be strings');
      }
      return '{${referenceKeyOrder(map.keys.cast<String>()).map((key) => '${jsonEncode(key)}:${spaced ? ' ' : ''}${encode(map[key])}').join(separator)}}';
    } finally {
      ancestors.remove(current);
    }
  }

  return encode(value);
}

String serializeState(Object? state) =>
    state is String ? state : referenceJson(state);
