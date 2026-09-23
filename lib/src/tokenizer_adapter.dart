/// Implementations must encode without automatic special tokens.
/// A compatible NFC + ByteLevel BPE implementation still needs mobile parity.
abstract interface class LayaTokenizer {
  List<int> encode(String text);
  int? tokenToId(String token);
}

final class SpecialTokenIds {
  const SpecialTokenIds({
    required this.cls,
    required this.sep,
    required this.mask,
    required this.pad,
    this.maskToken = '[MASK]',
  });

  factory SpecialTokenIds.fromTokenizer(LayaTokenizer tokenizer) {
    int lookup(String token) {
      final id = tokenizer.tokenToId(token);
      if (id == null || id < 0) {
        throw FormatException('Tokenizer is missing special token $token');
      }
      return id;
    }

    return SpecialTokenIds(
      cls: lookup('[CLS]'),
      sep: lookup('[SEP]'),
      mask: lookup('[MASK]'),
      pad: lookup('[PAD]'),
    );
  }

  final int cls;
  final int sep;
  final int mask;
  final int pad;
  final String maskToken;
}
