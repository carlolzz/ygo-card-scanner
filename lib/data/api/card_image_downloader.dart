import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Downloads a card's art to local device storage. YGOPRODeck's API guide
/// prohibits hotlinking images directly from their CDN, so every image is
/// fetched once and re-hosted from the app's own documents directory.
class CardImageDownloader {
  CardImageDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Downloads the image at [imageUrl] for [passcode] and returns the local
  /// file path it was saved to. Throws on any network/disk failure — the
  /// caller decides how to handle that.
  ///
  /// [passcode] must be all digits: it is interpolated into the save path
  /// (`<passcode>.jpg`), so validating it here keeps a non-numeric value
  /// (which YGOPRODeck never produces, but defense-in-depth) from escaping the
  /// images directory via `..` or a path separator.
  Future<String> download(String passcode, String imageUrl) async {
    if (!RegExp(r'^\d+$').hasMatch(passcode)) {
      throw ArgumentError.value(passcode, 'passcode', 'must be all digits');
    }
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'card_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final savePath = p.join(imagesDir.path, '$passcode.jpg');
    await _dio.download(imageUrl, savePath);
    return savePath;
  }
}
