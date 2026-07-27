import '../../core/theme/tokens.dart';
import 'hamming.dart';

/// One ranked hit from [HashIndex.rank]: a passcode and its Hamming distance to
/// the query hash.
class HashMatch {
  const HashMatch(this.passcode, this.distance);
  final String passcode;
  final int distance;
}

/// The in-memory perceptual-hash index: `passcode -> 256-bit pHash`, parsed
/// from the bundled `assets/card_hashes.json`. Pure and hardware-free, so tests
/// build one from a small in-memory map instead of the real asset (which
/// `rootBundle` makes awkward to load in unit tests).
class HashIndex {
  HashIndex({
    required this.version,
    required this.algorithm,
    required this.hashSize,
    required this.hashes,
  });

  /// Parses and validates the decoded `card_hashes.json` wrapper object. Throws
  /// [FormatException] if the header does not match what `phashFromLuma`
  /// produces (algorithm `phash`, hash size [kExpectedHashSize]) — a mismatched
  /// index would make every distance meaningless, so we fail loud rather than
  /// rank garbage.
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

  /// The hash size this runtime pHash is built for; the index must match.
  /// 16 -> a 16x16 DCT block -> [PerceptualHash.bitCount] bits.
  static const int kExpectedHashSize = 16;

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
  ///
  /// A bounded partial selection rather than collect-then-sort. The output is
  /// identical — same `(distance, passcode)` total order — but allocation is
  /// capped at [n] instead of the number of hits, which matters because the
  /// diagnostics path deliberately ranks with no distance limit: over 14.6k
  /// entries that was 14.6k `HashMatch` allocations plus a full sort (~200k
  /// comparisons through a closure) to take three, on the UI isolate, every
  /// frame — incurred exactly when someone has turned the overlay on to find out
  /// why scanning feels slow. [bound] tightening as the list fills also means an
  /// unlimited rank costs the same as a thresholded one after the first [n].
  List<HashMatch> rank(
    PerceptualHash query, {
    int n = 5,
    int maxDistance = PerceptualHash.bitCount,
  }) {
    if (n <= 0) return const [];
    final best = <HashMatch>[];
    var bound = maxDistance;
    hashes.forEach((passcode, hash) {
      final d = query.distanceTo(hash);
      if (d > bound) return;
      if (best.length == n) {
        final worst = best[n - 1];
        if (d > worst.distance ||
            (d == worst.distance && passcode.compareTo(worst.passcode) >= 0)) {
          return;
        }
      }
      var i = best.length;
      while (i > 0 && _precedes(d, passcode, best[i - 1])) {
        i--;
      }
      best.insert(i, HashMatch(passcode, d));
      if (best.length > n) {
        best.removeLast();
        // Never admit anything worse than the current n-th.
        bound = best[n - 1].distance;
      }
    });
    return best;
  }

  /// Whether `(distance, passcode)` sorts strictly before [other].
  static bool _precedes(int distance, String passcode, HashMatch other) =>
      other.distance > distance ||
      (other.distance == distance && other.passcode.compareTo(passcode) > 0);
}
