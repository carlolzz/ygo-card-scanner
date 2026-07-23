import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import 'art_matcher.dart';
import 'hash_index.dart';
import 'scan_providers.dart';

part 'art_providers.g.dart';

/// Path to the committed perceptual-hash index asset (built by
/// `tools/build_hash_index.py`, registered under `flutter: assets:`).
const String kCardHashesAsset = 'assets/card_hashes.json';

/// Loads and parses the bundled pHash index once. Tests override this with a
/// small in-memory [HashIndex] instead of loading the real asset via
/// `rootBundle`.
@riverpod
Future<HashIndex> hashIndex(Ref ref) async {
  final raw = await rootBundle.loadString(kCardHashesAsset);
  return HashIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// The artwork matcher the scan controller invokes. Composes the live camera,
/// the parsed index, and the card repository. Tests override this provider with
/// a fake returning canned candidates.
@riverpod
Future<ArtMatcher> artMatcher(Ref ref) async {
  final index = await ref.watch(hashIndexProvider.future);
  final repository = await ref.watch(cardRepositoryProvider.future);
  final camera = ref.watch(cameraServiceProvider);
  return PHashArtMatcher(
    camera: camera,
    index: index,
    repository: repository,
  );
}
