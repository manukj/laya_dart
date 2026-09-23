import 'dart:convert';
import 'dart:io';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'tokenizer_adapter.dart';

/// The NFC + ByteLevel BPE pipeline used by the English Laya checkpoint.
/// Encodes without the template post-processor (no automatic CLS/SEP).
final class ByteLevelBpeTokenizer implements LayaTokenizer {
  ByteLevelBpeTokenizer._(
    this._vocabulary,
    this._ranks,
    this._rawTokens,
    this._normalizedTokens,
  );

  factory ByteLevelBpeTokenizer.fromJson(
    Map<String, dynamic> json,
    Map<String, dynamic> config,
  ) {
    Never unsupported(String what) => throw FormatException(
      'Unsupported Laya tokenizer configuration: $what',
    );
    if (json['normalizer']?['type'] != 'NFC') {
      unsupported('normalizer must be NFC');
    }
    final pre = json['pre_tokenizer'];
    if (pre is! Map ||
        pre['type'] != 'ByteLevel' ||
        pre['add_prefix_space'] != false ||
        pre['use_regex'] != true) {
      unsupported('expected ByteLevel, add_prefix_space=false, use_regex=true');
    }
    if (json['truncation'] != null || json['padding'] != null) {
      unsupported('automatic truncation/padding');
    }
    final model = json['model'];
    if (model is! Map || model['type'] != 'BPE') {
      unsupported('model must be BPE');
    }
    for (final key in [
      'dropout',
      'unk_token',
      'continuing_subword_prefix',
      'end_of_word_suffix',
    ]) {
      if (model[key] != null) unsupported('BPE $key');
    }
    for (final key in ['fuse_unk', 'byte_fallback', 'ignore_merges']) {
      if (model[key] == true) unsupported('BPE $key');
    }
    for (final entry in {
      'cls_token': '[CLS]',
      'sep_token': '[SEP]',
      'mask_token': '[MASK]',
      'pad_token': '[PAD]',
    }.entries) {
      if (config[entry.key] != entry.value) unsupported(entry.key);
    }
    final vocabulary = Map<String, int>.from(model['vocab'] as Map);
    final ranks = <(String, String), int>{};
    for (final (rank, merge) in (model['merges'] as List).indexed) {
      final List pair = merge is String ? merge.split(' ') : merge as List;
      if (pair.length != 2 || pair.any((p) => p is! String)) {
        unsupported('invalid BPE merge');
      }
      final left = pair[0] as String;
      final right = pair[1] as String;
      if (!vocabulary.containsKey(left + right)) {
        unsupported('merge missing from vocabulary');
      }
      ranks[(left, right)] = rank;
    }
    final raw = <_AddedToken>[];
    final normalized = <_AddedToken>[];
    for (final token in json['added_tokens'] as List) {
      if (token['single_word'] != false) unsupported('single_word added token');
      final text = token['content'] as String;
      final id = token['id'] as int;
      if (text.isEmpty || id < 0) unsupported('invalid added token');
      vocabulary[text] = id;
      final added = _AddedToken(
        text,
        id,
        token['lstrip'] == true,
        token['rstrip'] == true,
      );
      (token['normalized'] == true ? normalized : raw).add(added);
    }
    for (final tokens in [raw, normalized]) {
      tokens.sort((a, b) => b.text.length.compareTo(a.text.length));
    }
    final tokenizer = ByteLevelBpeTokenizer._(
      vocabulary,
      ranks,
      raw,
      normalized,
    );
    SpecialTokenIds.fromTokenizer(tokenizer);
    return tokenizer;
  }

  static Future<ByteLevelBpeTokenizer> fromDirectory(String directory) async {
    final data = jsonDecode(
      await File('$directory/tokenizer.json').readAsString(),
    );
    final config = jsonDecode(
      await File('$directory/tokenizer_config.json').readAsString(),
    );
    if (data is! Map<String, dynamic> || config is! Map<String, dynamic>) {
      throw const FormatException('Tokenizer files must contain JSON objects');
    }
    return ByteLevelBpeTokenizer.fromJson(data, config);
  }

  final Map<String, int> _vocabulary;
  final Map<(String, String), int> _ranks;
  final List<_AddedToken> _rawTokens;
  final List<_AddedToken> _normalizedTokens;
  final Map<String, List<int>> _cache = {};

  // Unicode White_Space used by the reference ByteLevel regex. ECMAScript's
  // \s differs for U+0085 and U+FEFF, so keep the set explicit.
  static const _space =
      r'\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000';
  static final _word = RegExp(
    "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^$_space\\p{L}\\p{N}]+|[$_space]+(?![^$_space])|[$_space]+",
    unicode: true,
  );
  static final _trailingSpace = RegExp('[$_space]+\$', unicode: true);
  static final _leadingSpace = RegExp('^[$_space]+', unicode: true);
  static final _bytes = _byteAlphabet();

  static List<String> _byteAlphabet() {
    final visible = [
      ...List.generate(94, (i) => i + 33),
      ...List.generate(12, (i) => i + 161),
      ...List.generate(78, (i) => i + 174),
    ];
    final codePoints = List<int>.from(visible);
    var extra = 0;
    for (var byte = 0; byte < 256; byte++) {
      if (!visible.contains(byte)) {
        visible.add(byte);
        codePoints.add(256 + extra++);
      }
    }
    final alphabet = List<String>.filled(256, '');
    for (var i = 0; i < visible.length; i++) {
      alphabet[visible[i]] = String.fromCharCode(codePoints[i]);
    }
    return alphabet;
  }

  @override
  int? tokenToId(String token) => _vocabulary[token];

  @override
  List<int> encode(String text) {
    final result = <int>[];
    _splitAdded(text, _rawTokens, result, (part) {
      _splitAdded(unorm.nfc(part), _normalizedTokens, result, (normalized) {
        for (final match in _word.allMatches(normalized)) {
          result.addAll(_bpe(match.group(0)!));
        }
      });
    });
    return result;
  }

  void _splitAdded(
    String text,
    List<_AddedToken> tokens,
    List<int> output,
    void Function(String) ordinary,
  ) {
    var offset = 0;
    while (offset < text.length) {
      _AddedToken? next;
      var position = text.length;
      for (final token in tokens) {
        final found = text.indexOf(token.text, offset);
        if (found >= 0 &&
            (found < position || (found == position && next == null))) {
          position = found;
          next = token;
        }
      }
      if (next == null) {
        ordinary(text.substring(offset));
        break;
      }
      var before = text.substring(offset, position);
      if (next.leftStrip) before = before.replaceFirst(_trailingSpace, '');
      if (before.isNotEmpty) ordinary(before);
      output.add(next.id);
      offset = position + next.text.length;
      if (next.rightStrip) {
        final spaces = _leadingSpace.firstMatch(text.substring(offset));
        if (spaces != null) offset += spaces.end;
      }
    }
  }

  List<int> _bpe(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    var pieces = utf8.encode(text).map((byte) => _bytes[byte]).toList();
    while (pieces.length > 1) {
      var bestRank = 0x7fffffffffffffff;
      (String, String)? best;
      for (var i = 0; i < pieces.length - 1; i++) {
        final pair = (pieces[i], pieces[i + 1]);
        final rank = _ranks[pair];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          best = pair;
        }
      }
      if (best == null) break;
      final merged = <String>[];
      for (var i = 0; i < pieces.length; i++) {
        if (i + 1 < pieces.length && (pieces[i], pieces[i + 1]) == best) {
          merged.add(pieces[i] + pieces[++i]);
        } else {
          merged.add(pieces[i]);
        }
      }
      pieces = merged;
    }
    final ids = List<int>.unmodifiable(
      pieces.map(
        (piece) =>
            _vocabulary[piece] ??
            (throw FormatException('Missing byte/BPE token: $piece')),
      ),
    );
    if (_cache.length >= 4096) _cache.remove(_cache.keys.first);
    if (text.length <= 256) _cache[text] = ids;
    return ids;
  }
}

final class _AddedToken {
  const _AddedToken(this.text, this.id, this.leftStrip, this.rightStrip);
  final String text;
  final int id;
  final bool leftStrip;
  final bool rightStrip;
}
