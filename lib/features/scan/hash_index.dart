import '../../core/theme/tokens.dart';
import 'hamming.dart';

/// One ranked hit from [HashIndex.rank]: a passcode and its Hamming distance to
/// the query hash.
class HashMatch {
  const HashMatch(this.passcode, this.distance);
  final String passcode;
  final int distance;
}

/// The in-memory perceptual-hash index: `passcode -> 64-bit pHash`, parsed from
/// the bundled `assets/card_hashes.json`. Pure and hardware-free, so tests build
/// one from a small in-memory map instead of the real asset (which `rootBundle`
/// makes awkward to load in unit tests).
class HashIndex {
  HashIndex({
    required this.version,
    required this.algorithm,
    required this.hashSize,
    required this.hashes,
  });

  /// Parses and validates the decoded `card_hashes.json` wrapper object. Throws
  /// [FormatException] if the header does not match what `phashFromLuma`
  /// produces (algorithm `phash`, hash size 8) — a mismatched index would make
  /// every distance meaningless, so we fail loud rather than rank garbage.
  factory HashIndex.fromJson(Map<String, dynamic> json) {
    final algorithm = json['algorithm'];
    final hashSize = json['hash_size'];
    if (algorithm != 'phash') {
      throw FormatException('unsupported hash algorithm: $algorithm');
    }
    if (hashSize != kExpectedHashSize) {
      throw FormatException('unsupported hash size: $hashSize');
    }
    // The index records the crop its hashes were taken from. If that ever
    // parts company with what the runtime crops, every distance degrades
    // quietly — no error, just worse recognition — so compare them here.
    // Absent on v1 indexes, which predate the header; nothing to check then.
    final rawRoi = json['roi'];
    if (rawRoi is List && rawRoi.length == 4) {
      final roi = [for (final value in rawRoi) (value as num).toDouble()];
      const expected = ArtMatchTuning.artBoxRoi;
      final matches =
          (roi[0] - expected.left).abs() <= _roiTolerance &&
          (roi[1] - expected.top).abs() <= _roiTolerance &&
          (roi[2] - expected.right).abs() <= _roiTolerance &&
          (roi[3] - expected.bottom).abs() <= _roiTolerance;
      if (!matches) {
        throw FormatException(
          'index built for art-box ROI $roi, but this build crops '
          '$expected — rebuild assets/card_hashes.json '
          '(tools/build_hash_index.py) or restore ArtMatchTuning.artBoxRoi',
        );
      }
    }
    final rawHashes = json['hashes'];
    if (rawHashes is! Map) {
      throw const FormatException('missing "hashes" map');
    }
    final parsed = <String, PerceptualHash>{};
    rawHashes.forEach((key, value) {
      parsed[key as String] = PerceptualHash.parseHex(value as String);
    });
    return HashIndex(
      version: json['version'] as int? ?? 0,
      algorithm: algorithm as String,
      hashSize: hashSize as int,
      hashes: parsed,
    );
  }

  /// The hash size (8) this runtime pHash is built for; the index must match.
  static const int kExpectedHashSize = 8;

  /// Slop when comparing the index's recorded ROI to this build's — the header
  /// stores rounded decimals, so an exact comparison would be brittle.
  static const double _roiTolerance = 0.0005;

  final int version;
  final String algorithm;
  final int hashSize;
  final Map<String, PerceptualHash> hashes;

  int get length => hashes.length;

  /// The [n] closest passcodes to [query] within [maxDistance], nearest first.
  /// Ties break by passcode for a stable order.
  List<HashMatch> rank(
    PerceptualHash query, {
    int n = 5,
    int maxDistance = 64,
  }) {
    final hits = <HashMatch>[];
    hashes.forEach((passcode, hash) {
      final d = query.distanceTo(hash);
      if (d <= maxDistance) hits.add(HashMatch(passcode, d));
    });
    hits.sort((a, b) {
      final byDistance = a.distance.compareTo(b.distance);
      return byDistance != 0 ? byDistance : a.passcode.compareTo(b.passcode);
    });
    return hits.length <= n ? hits : hits.sublist(0, n);
  }
}
