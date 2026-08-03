import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How many card images may be downloading at once.
///
/// Matches `tools/build_hash_index.py`'s `--workers 4` default, which is the
/// posture `tools/README.md` records for YGOPRODeck's API guide.
const int kMaxConcurrentDownloads = 4;

/// Caps how many operations run at once, queueing the rest in submission order.
///
/// A completer FIFO rather than a package: the approved stack has no semaphore
/// and this is the whole of it.
///
/// It exists because a minified collection grid puts 15-30 cells on screen at
/// once, and after a CSV import every one of them has to fetch its artwork — so
/// without a cap, one scroll is thirty simultaneous requests at YGOPRODeck.
/// A *cap*, not a delay: the tool's `--delay` is right for a 14 000-image batch
/// run and wrong for a grid someone is looking at, where it would visibly fill
/// one cell at a time.
class ConcurrencyLimiter {
  ConcurrencyLimiter(this.maxConcurrent) : assert(maxConcurrent > 0, '');

  final int maxConcurrent;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _running = 0;

  /// Runs [body] once a slot is free, and releases the slot however it ends.
  Future<T> run<T>(Future<T> Function() body) async {
    if (_running >= maxConcurrent) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await body();
    } finally {
      _running--;
      // A throwing body must hand its slot on, or a few failures deadlock every
      // later download for the life of the app.
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}

/// Downloads a card's art to local device storage. YGOPRODeck's API guide
/// prohibits hotlinking images directly from their CDN, so every image is
/// fetched once and re-hosted from the app's own documents directory.
class CardImageDownloader {
  CardImageDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Shared by every caller — the scan candidates, `addOrIncrement`'s
  /// fire-and-forget, and now a whole grid of freshly imported cards. The
  /// downloader is the one choke point they all already pass through.
  static final ConcurrencyLimiter _limiter = ConcurrencyLimiter(
    kMaxConcurrentDownloads,
  );

  /// Downloads the image at [imageUrl] for [passcode] and returns the local
  /// file path it was saved to. Throws on any network/disk failure — the
  /// caller decides how to handle that.
  ///
  /// [passcode] must be all digits: it is interpolated into the save path
  /// (`<passcode>.jpg`), so validating it here keeps a non-numeric value
  /// (which YGOPRODeck never produces, but defense-in-depth) from escaping the
  /// images directory via `..` or a path separator. The check is deliberately
  /// *outside* the concurrency gate: a malformed passcode is a programming
  /// error and should not wait in a queue to say so.
  Future<String> download(String passcode, String imageUrl) async {
    if (!RegExp(r'^\d+$').hasMatch(passcode)) {
      throw ArgumentError.value(passcode, 'passcode', 'must be all digits');
    }
    return _limiter.run(() async {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(dir.path, 'card_images'));
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final savePath = p.join(imagesDir.path, '$passcode.jpg');
      await _dio.download(imageUrl, savePath);
      return savePath;
    });
  }
}
