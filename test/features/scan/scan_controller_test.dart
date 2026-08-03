import 'dart:async';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/features/scan/art_matcher.dart';
import 'package:ygo_scanner/features/scan/art_providers.dart';
import 'package:ygo_scanner/features/scan/frame_quality.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';
import 'package:ygo_scanner/features/scan/scan_controller.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
import 'package:ygo_scanner/features/scan/scan_sample.dart';
import 'package:ygo_scanner/features/scan/scan_state.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';

/// Fake matcher so the controller's artwork resolution runs without a camera,
/// image asset, or pHash math — the continuous ranking is driven by the
/// overridden [artReadingsProvider], and this just resolves the agreed run.
class _FakeArtMatcher implements ArtMatcher {
  _FakeArtMatcher(this.result, {this.guesses = const []});
  final List<ArtCandidate> result;

  /// What the *unthresholded* nearest few resolve to — deliberately a separate
  /// list, since the whole point of `bestGuesses` is answering when `match`
  /// cannot.
  final List<ArtCandidate> guesses;
  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async => result;
  @override
  Future<List<ArtCandidate>> bestGuesses() async => guesses;
  @override
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  }) async => const ArtFrameResult(ArtFrameStatus.notDetected, []);
  @override
  ArtSample? get lastSample => null;
}

/// A matcher whose resolution fails. Stands in for a sqflite hiccup or a
/// detector/index failure mid-resolve — the case that used to leave
/// `scanPaused` true forever *and* drop an unhandled async error, since
/// `_resolveArtMatch` is called unawaited from a `ref.listen` callback.
class _ThrowingArtMatcher implements ArtMatcher {
  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async =>
      throw StateError('resolution failed');
  @override
  Future<List<ArtCandidate>> bestGuesses() async =>
      throw StateError('resolution failed');
  @override
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  }) async => const ArtFrameResult(ArtFrameStatus.notDetected, []);
  @override
  ArtSample? get lastSample => null;
}

/// A matcher that blocks in `match` until the test releases it, so a test can
/// interleave a frame with a resolution that is still in flight.
class _GatedArtMatcher implements ArtMatcher {
  _GatedArtMatcher(this.gate, this.result);
  final Completer<void> gate;
  final List<ArtCandidate> result;
  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async {
    await gate.future;
    return result;
  }

  @override
  Future<List<ArtCandidate>> bestGuesses() async => const [];
  @override
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  }) async => const ArtFrameResult(ArtFrameStatus.notDetected, []);
  @override
  ArtSample? get lastSample => null;
}

// Seeded fixture passcodes (see fake_collection_seed.dart).
const darkMagician = '46986414';
const blueEyes = '89631139';
const unknownPasscode = '00000000';

const dmCard =
    YgoCard(passcode: darkMagician, name: 'Dark Magician', type: 'Normal Monster');
const beCard = YgoCard(
  passcode: blueEyes,
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
);

// The scan pipeline resolves through the sqflite_common_ffi background
// isolate; a real delay (not a fake clock) lets stream events and db round
// trips actually complete.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late Database db;
  late StreamController<ArtReading> artReadings;
  late StreamController<PasscodeReading> readings;
  late ProviderContainer container;
  var artSeq = 0;
  var ocrSeq = 0;
  // Mutated by tests before triggering an artwork match.
  var fakeCandidates = <ArtCandidate>[];
  var fakeGuesses = <ArtCandidate>[];

  /// Set by tests that need a matcher which throws or blocks; null means the
  /// default [_FakeArtMatcher] over [fakeCandidates]/[fakeGuesses].
  ArtMatcher? fakeMatcher;

  /// One frame of artwork: a nearest hit at [distance], or nothing (null).
  Future<void> feedArt(
    String? passcode, {
    int distance = 2,
    ArtFrameStatus status = ArtFrameStatus.noFrame,
    FrameQuality? quality,
  }) async {
    artReadings.add(
      ArtReading(
        artSeq++,
        passcode == null ? null : HashMatch(passcode, distance),
        status: status,
        quality: quality,
      ),
    );
    await settle();
  }

  /// A frame where a card was found and rectified but its art crop was rejected
  /// before hashing — the blur/glare gate.
  Future<void> feedLowQuality({bool glare = false}) => feedArt(
    null,
    status: ArtFrameStatus.lowQuality,
    quality: glare
        ? const FrameQuality(sharpness: 9999, glare: 0.9)
        : const FrameQuality(sharpness: 0, glare: 0),
  );

  /// A frame where a card was detected and hashed but nothing ranked close
  /// enough to auto-present — the state that used to render "Point at a card".
  Future<void> feedUnmatched() => feedArt(
    null,
    status: ArtFrameStatus.detected,
    quality: const FrameQuality(sharpness: 9999, glare: 0),
  );

  Future<void> feedOcr(String? passcode) async {
    readings.add(PasscodeReading(ocrSeq++, passcode));
    await settle();
  }

  /// Drives exactly N agreeing, in-gate artwork frames — enough to resolve a
  /// match. Tied to [ScanTuning.artAgreementFrames] so it feeds the threshold
  /// precisely (feeding extra frames would start a fresh run after the resolve).
  Future<void> agreeArt(String passcode) async {
    for (var i = 0; i < ScanTuning.artAgreementFrames; i++) {
      await feedArt(passcode);
    }
    await settle();
  }

  ScanState state() => container.read(scanControllerProvider);
  ScanController controller() =>
      container.read(scanControllerProvider.notifier);

  setUp(() async {
    db = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(db);
    artReadings = StreamController<ArtReading>.broadcast();
    readings = StreamController<PasscodeReading>.broadcast();
    artSeq = 0;
    ocrSeq = 0;
    fakeCandidates = <ArtCandidate>[];
    fakeGuesses = <ArtCandidate>[];
    fakeMatcher = null;
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        artReadingsProvider.overrideWith((ref) => artReadings.stream),
        passcodeReadingsProvider.overrideWith((ref) => readings.stream),
        artMatcherProvider.overrideWith(
          (ref) async =>
              fakeMatcher ??
              _FakeArtMatcher(fakeCandidates, guesses: fakeGuesses),
        ),
      ],
    );
    // Keep the controller alive so its stream subscriptions stay registered.
    container.listen(scanControllerProvider, (previous, next) {});
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await artReadings.close();
    await readings.close();
    await db.close();
  });

  test('starts in the detecting state', () {
    expect(state().status, ScanStatus.detecting);
  });

  group('primary path: artwork', () {
    test('fewer than N agreeing artwork reads stays reading', () async {
      // One short of the threshold: mid-run, not yet resolved.
      for (var i = 0; i < ScanTuning.artAgreementFrames - 1; i++) {
        await feedArt(darkMagician);
      }
      expect(state().status, ScanStatus.reading);
      expect(state().matchedCard, isNull);
    });

    test('N agreeing in-gate reads resolve to a match with defaults', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.name, 'Dark Magician');
      expect(state().condition, CardCondition.nearMint);
    });

    // The headline change of this pass, and the exact inverse of what this test
    // used to assert. A hit past `autoMatchMaxDistance` but inside
    // `maxHammingDistance` was routed into the empty-frame branch and reported
    // as "can't identify this card"; on device the guess in that band was right
    // every time it was asked for. It is presented now — as a guess.
    test('a read past the confidence boundary still resolves to a match',
        () async {
      const far = ArtMatchTuning.autoMatchMaxDistance + 2;
      fakeCandidates = [const ArtCandidate(dmCard, far)];
      for (var i = 0; i < ScanTuning.artAgreementFrames; i++) {
        await feedArt(darkMagician, distance: far);
      }
      await settle();

      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.name, 'Dark Magician');
      // What the review gate reads to decide whether to hedge.
      expect(state().matchedDistance, far);
      expect(
        state().matchedDistance!,
        greaterThan(ArtMatchTuning.autoMatchMaxDistance),
      );
    });

    test('a confident read carries its distance without hedging', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.matched);
      expect(state().matchedDistance, 2);
      expect(
        state().matchedDistance!,
        lessThanOrEqualTo(ArtMatchTuning.autoMatchMaxDistance),
      );
    });

    test('a frame with nothing ranked at all never accumulates', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      for (var i = 0; i < 5; i++) {
        await feedUnmatched();
      }
      expect(state().status, ScanStatus.detecting);
      expect(state().matchedCard, isNull);
    });

    test('disagreeing artwork reads discard the run', () async {
      await feedArt(darkMagician);
      await feedArt(blueEyes); // disagreement clears the run
      await feedArt(darkMagician);
      await settle();
      expect(state().status, ScanStatus.reading);
      expect(state().matchedCard, isNull);
    });

    test('an unresolvable agreed run (no candidates) keeps scanning', () async {
      fakeCandidates = []; // e.g. nearest hits are alt-arts not in the app DB
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.detecting);
      expect(state().matchedCard, isNull);
    });

    test('confirm writes the reviewed match and resumes', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);

      await controller().confirm();
      await settle();

      final scanned = (await CollectionDao(db).getEntriesForPasscode(darkMagician))
          .where(
        (e) => e.condition == CardCondition.nearMint && e.printingId == null,
      );
      expect(scanned, hasLength(1));
      expect(scanned.first.quantity, 1);
      expect(state().status, ScanStatus.confirmed);
    });

    test('the same card is debounced until the frame goes empty', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      await controller().confirm();
      await settle();

      // Still in view: re-reads must NOT re-match.
      await feedArt(darkMagician);
      await feedArt(darkMagician);
      await feedArt(darkMagician);
      expect(state().status, isNot(ScanStatus.matched));

      // Leaves the frame for M empty frames, then returns.
      for (var i = 0; i < ScanTuning.debounceEmptyFrames; i++) {
        await feedArt(null);
      }
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.matched);
    });

    test('"not the right card" reveals candidates; a pick re-enters review',
        () async {
      fakeCandidates = [
        const ArtCandidate(dmCard, 2),
        const ArtCandidate(beCard, 4),
      ];
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.passcode, darkMagician);

      controller().showCandidates();
      expect(state().status, ScanStatus.candidates);
      expect(state().candidates, hasLength(2));

      controller().selectCandidate(beCard);
      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.passcode, blueEyes);
      expect(state().condition, CardCondition.nearMint);
    });

    test('dismiss from a match returns to detecting', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      controller().dismiss();
      expect(state().status, ScanStatus.detecting);
      expect(state().candidates, isEmpty);
    });

    test('a dismissed card is not re-matched on the very next frame', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      controller().dismiss();

      // The card is still under the lens the instant the panel closes; without
      // a cooldown it would re-open under the user's thumb.
      await feedArt(darkMagician);
      expect(state().status, ScanStatus.detecting);
      expect(state().matchedCard, isNull);
    });

    test('a dismissed card is re-matchable without leaving the frame', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      controller().dismiss();

      // The regression this guards: a dismiss used to reuse the *post-confirm*
      // debounce, which only advances on frames with no confident match. The
      // dismissed card sitting in the reticle matched every frame, so the
      // counter was pinned at zero and the card could never be picked up again
      // while the user held it still. Note there is not one empty frame here.
      for (var i = 0; i < ScanTuning.dismissCooldownFrames; i++) {
        await feedArt(darkMagician);
      }
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.passcode, darkMagician);
    });

    test('a confirmed card is not freed by the dismiss cooldown', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      await controller().confirm();
      await settle();

      // The two debounces must stay distinct: a confirm wrote a row, so the
      // card has to leave the lens no matter how many frames pass with it in
      // view. Feeding well past the dismiss cooldown proves it isn't shared.
      for (var i = 0; i < ScanTuning.dismissCooldownFrames * 3; i++) {
        await feedArt(darkMagician);
      }
      expect(state().status, isNot(ScanStatus.matched));
    });

    test('dismissing a candidate list suppresses the top guess', () async {
      fakeCandidates = [
        const ArtCandidate(dmCard, 2),
        const ArtCandidate(beCard, 4),
      ];
      await agreeArt(darkMagician);
      controller().showCandidates();
      // `showCandidates` clears `matchedCard`, so "none of these" has to fall
      // back to the top candidate or it would suppress nothing at all.
      controller().dismiss();

      await feedArt(darkMagician);
      expect(state().status, ScanStatus.detecting);
      expect(state().matchedCard, isNull);
    });

    group('the debounce is keyed on the index passcode, not the card', () {
      // The index keys every `card_images[i].id` (alt-arts included) while the
      // `cards` table stores only `card_images[0]`, and `PHashArtMatcher.match`
      // resolves an alt-art hash to the *base* card. So on those matches the
      // confirmed card's passcode is NOT the passcode the next frame's reading
      // carries, and a debounce comparing them can never fire.
      const altArtId = '46986415'; // an alt-art of Dark Magician
      setUp(() {
        fakeCandidates = [
          const ArtCandidate(dmCard, 2, rankedPasscode: altArtId),
        ];
      });

      test('a confirmed alt-art match is not immediately re-presented',
          () async {
        await agreeArt(altArtId);
        await controller().confirm();
        await settle();

        // Exactly the reported failure: the card is still under the lens, and
        // the review panel re-opens on the card just logged — the "one card
        // logs thirty times" case the debounce exists to prevent.
        for (var i = 0; i < ScanTuning.artAgreementFrames * 2; i++) {
          await feedArt(altArtId);
        }
        expect(state().status, isNot(ScanStatus.matched));
      });

      test('a dismissed alt-art match respects its cooldown', () async {
        await agreeArt(altArtId);
        controller().dismiss();

        await feedArt(altArtId);
        expect(state().status, ScanStatus.detecting);
        expect(state().matchedCard, isNull);
      });
    });

    group('image-quality gate', () {
      // The reason the gate exists. A hand-held card reads cleanly most of the
      // time but blinks: one glare frame, one shake. Those frames used to take
      // the empty-frame branch, which *clears* the agreement buffer — so a card
      // that was 80% readable could never accumulate `artAgreementFrames`
      // consecutive good frames and simply never resolved.
      test('a rejected frame does not clear a run of agreement', () async {
        fakeCandidates = [const ArtCandidate(beCard, 2)];
        // One good frame, one bad, then enough good ones to reach the gate.
        await feedArt(blueEyes);
        expect(state().artAgreementBuffer, [blueEyes]);

        await feedLowQuality();
        expect(
          state().artAgreementBuffer,
          [blueEyes],
          reason: 'the skipped frame must neither confirm nor contradict',
        );

        for (var i = 1; i < ScanTuning.artAgreementFrames; i++) {
          await feedArt(blueEyes);
        }
        await settle();
        expect(state().status, ScanStatus.matched);
      });

      // `emptyFrameCount` drives the post-confirm debounce, the spec's
      // non-optional guard against one card logging thirty times. A stream of
      // unreadable frames must not be able to retire a confirmed card's
      // suppression while it is still sitting under the lens.
      test('a rejected frame does not advance the post-confirm debounce',
          () async {
        await feedArt(null);
        expect(state().emptyFrameCount, 1);

        await feedLowQuality();
        expect(state().emptyFrameCount, 1);
      });

      test('it reports blur and glare separately', () async {
        await feedLowQuality();
        expect(state().hint, ScanHint.blurry);

        await feedLowQuality(glare: true);
        expect(state().hint, ScanHint.glare);
      });

      // The failsafe. Both thresholds are absolute values on a scene-dependent
      // measure; if they are wrong for some device the failure mode without
      // this is that recognition never works again, with every on-screen signal
      // still green.
      test('the gate stops rejecting after a streak, so it cannot wedge',
          () async {
        for (var i = 0; i < FrameQualityTuning.maxConsecutiveSkips; i++) {
          await feedLowQuality();
          expect(state().qualitySkipStreak, i + 1);
        }
        // Past the cap the frame falls through to the normal path, which for a
        // reading carrying no match is the empty-frame branch.
        await feedLowQuality();
        expect(state().emptyFrameCount, 1);
        expect(state().qualitySkipStreak, 0);
      });

      test('a good frame clears the skip streak', () async {
        await feedLowQuality();
        expect(state().qualitySkipStreak, 1);

        await feedArt(blueEyes);
        expect(state().qualitySkipStreak, 0);
        expect(state().hint, ScanHint.none);
      });
    });

    group('detected but unidentified', () {
      // The headline defect. A frame that found, rectified and hashed the card
      // but matched nothing left the machine in `detecting`, which the banner
      // rendered as "Point at a card" — telling the user to do the one thing
      // they were already doing, with no way out.
      test('a detected-but-unmatched frame is not reported as an empty frame',
          () async {
        await feedUnmatched();
        expect(state().status, ScanStatus.detecting);
        expect(state().unmatchedStreak, 1);
        expect(state().hint, ScanHint.identifying);
      });

      test('a frame with no card at all still reports nothing', () async {
        await feedArt(null);
        expect(state().unmatchedStreak, 0);
        expect(state().hint, ScanHint.none);
      });

      test('the banner becomes actionable after a streak', () async {
        for (var i = 0; i < FrameQualityTuning.unmatchedStreakForHint - 1; i++) {
          await feedUnmatched();
          expect(state().hint, ScanHint.identifying);
        }
        await feedUnmatched();
        expect(state().hint, ScanHint.unidentified);
      });

      test('a card coming into range clears the streak', () async {
        await feedUnmatched();
        await feedUnmatched();
        expect(state().unmatchedStreak, 2);

        await feedArt(blueEyes);
        expect(state().unmatchedStreak, 0);
        expect(state().hint, ScanHint.none);
      });

      // The escape hatch: `showCandidates` is guarded on `matched` and could not
      // be reached from here, so nothing was offered at all.
      test('showBestGuesses resolves the last frame into the candidate panel',
          () async {
        fakeCandidates = const [ArtCandidate(dmCard, 40)];
        await feedUnmatched();
        await controller().showBestGuesses();
        await settle();

        expect(state().status, ScanStatus.candidates);
        expect(state().candidates.single.card.passcode, dmCard.passcode);
        expect(state().hint, ScanHint.none);
      });

      // Now that every in-threshold hit auto-presents, getting here at all means
      // `match` has nothing: the useful answer is the unthresholded nearest few.
      test('showBestGuesses falls back to the unthresholded nearest', () async {
        fakeCandidates = const [];
        fakeGuesses = const [ArtCandidate(beCard, 96)];
        await feedUnmatched();
        await controller().showBestGuesses();
        await settle();

        expect(state().status, ScanStatus.candidates);
        expect(state().candidates.single.card.passcode, beCard.passcode);
      });

      test('showBestGuesses with nothing ranked at all resumes instead of '
          'showing an empty panel', () async {
        fakeCandidates = const [];
        fakeGuesses = const [];
        await feedUnmatched();
        await controller().showBestGuesses();
        await settle();

        expect(state().status, ScanStatus.detecting);
        expect(state().candidates, isEmpty);
        expect(
          state().unmatchedStreak,
          0,
          reason: 'or the offer is re-made on the very next frame',
        );
      });

      test('a pick from those guesses goes through the same review gate',
          () async {
        fakeCandidates = const [ArtCandidate(dmCard, 40)];
        await feedUnmatched();
        await controller().showBestGuesses();
        await settle();

        controller().selectCandidate(dmCard);
        expect(state().status, ScanStatus.matched);
        expect(state().matchedCard, dmCard);
      });

      test('showBestGuesses is inert once a result already awaits the user',
          () async {
        fakeCandidates = [const ArtCandidate(beCard, 2)];
        await agreeArt(blueEyes);
        expect(state().status, ScanStatus.matched);

        await controller().showBestGuesses();
        expect(state().status, ScanStatus.matched);
      });
    });
  });

  group('fallback path: on-demand passcode OCR', () {
    test('request then N agreeing reads that hit the db resolve to a match',
        () async {
      controller().requestPasscodeRead();
      expect(state().status, ScanStatus.readingCode);

      await feedOcr(darkMagician);
      await feedOcr(darkMagician);
      await feedOcr(darkMagician);
      await settle();

      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.name, 'Dark Magician');
    });

    test('a read with no db hit resolves to unknown', () async {
      controller().requestPasscodeRead();
      await feedOcr(unknownPasscode);
      await feedOcr(unknownPasscode);
      await feedOcr(unknownPasscode);
      await settle();

      expect(state().status, ScanStatus.unknown);
      expect(state().unknownPasscode, unknownPasscode);
    });

    test('requesting a read while a match awaits is ignored', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.matched);
      controller().requestPasscodeRead();
      expect(state().status, ScanStatus.matched);
    });
  });

  group('passcode mode is sticky', () {
    Future<void> readCode(String passcode) async {
      for (var i = 0; i < ScanTuning.agreementFrames; i++) {
        await feedOcr(passcode);
      }
      await settle();
    }

    test('a confirm resumes reading codes instead of artwork', () async {
      controller().requestPasscodeRead();
      await readCode(darkMagician);
      expect(state().status, ScanStatus.matched);

      await controller().confirm();
      await settle();

      // The whole point: logging a card must not drop the user back into
      // artwork recognition, or every card in a stack costs an extra tap.
      expect(state().mode, ScanMode.passcode);
      expect(state().status, ScanStatus.readingCode);
    });

    test('a dismiss also stays in the mode', () async {
      controller().requestPasscodeRead();
      await readCode(darkMagician);
      controller().dismiss();

      expect(state().mode, ScanMode.passcode);
      expect(state().status, ScanStatus.readingCode);
    });

    test('a dismissed code is re-readable without leaving the frame', () async {
      controller().requestPasscodeRead();
      await readCode(darkMagician);
      controller().dismiss();

      // Same trap as the artwork path, and it was in both: nothing was written,
      // so the code must become readable again with the card held still.
      for (var i = 0; i < ScanTuning.dismissCooldownFrames; i++) {
        await feedOcr(darkMagician);
      }
      await readCode(darkMagician);

      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.passcode, darkMagician);
    });

    test('artwork readings are ignored while the mode is on', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      controller().requestPasscodeRead();
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.readingCode);
      expect(state().matchedCard, isNull);
    });

    test('a confirmed card is not re-read until it leaves the frame', () async {
      controller().requestPasscodeRead();
      await readCode(darkMagician);
      await controller().confirm();
      await settle();

      // Still under the lens: reads of the same code must not re-open review.
      await readCode(darkMagician);
      expect(state().status, ScanStatus.readingCode);

      // Empty frames advance the debounce; then the same card is fair game.
      for (var i = 0; i < ScanTuning.debounceEmptyFrames; i++) {
        await feedOcr(null);
      }
      await readCode(darkMagician);
      expect(state().status, ScanStatus.matched);
    });

    test('exiting the mode returns to artwork recognition', () async {
      controller().requestPasscodeRead();
      expect(state().status, ScanStatus.readingCode);

      controller().exitPasscodeMode();
      expect(state().mode, ScanMode.artwork);
      expect(state().status, ScanStatus.detecting);

      // And artwork is live again.
      fakeCandidates = [const ArtCandidate(dmCard, 2)];
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.matched);
    });
  });

  test('the set picked in the review gate is written to the entry', () async {
    final printing = (await PrintingDao(db).getForPasscode(blueEyes)).first;
    fakeCandidates = [const ArtCandidate(beCard, 2)];
    await agreeArt(blueEyes);
    expect(state().status, ScanStatus.matched);
    // A scan starts on "no specific set" — the camera can't read the set code.
    expect(state().printingId, isNull);

    controller().setPrinting(printing.id);
    await controller().confirm();
    await settle();

    final scanned = (await CollectionDao(db).getEntriesForPasscode(blueEyes))
        .where((e) => e.edition == CardEdition.unlimited);
    expect(scanned, hasLength(1));
    expect(scanned.first.printingId, printing.id);
    // And the next card starts from "no specific set" again.
    expect(state().printingId, isNull);
  });

  test('setLanguage before confirm overrides the settings default', () async {
    fakeCandidates = [const ArtCandidate(beCard, 2)];
    await agreeArt(blueEyes);
    expect(state().status, ScanStatus.matched);

    // Camera can't read language, so it's picked by hand in the review gate.
    controller().setLanguage('IT');
    await controller().confirm();
    await settle();

    final scanned = (await CollectionDao(db).getEntriesForPasscode(blueEyes))
        .where((e) => e.printingId == null);
    expect(scanned, hasLength(1));
    expect(scanned.first.language, 'IT');
  });

  group('settings defaults', () {
    late ProviderContainer configured;

    setUp(() async {
      await SettingsRepository(MetaDao(db)).save(
        const AppSettings(
          defaultCondition: CardCondition.lightPlayed,
          defaultEdition: CardEdition.first,
          language: 'DE',
        ),
      );
      configured = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          artReadingsProvider.overrideWith((ref) => artReadings.stream),
          passcodeReadingsProvider.overrideWith((ref) => readings.stream),
          artMatcherProvider.overrideWith(
            (ref) async => _FakeArtMatcher(const [ArtCandidate(dmCard, 2)]),
          ),
        ],
      );
      // Settings are read synchronously at controller build, so they have to be
      // resolved first — exactly what App's gate guarantees in production.
      await configured.read(settingsControllerProvider.future);
      configured.listen(scanControllerProvider, (previous, next) {});
      await settle();
    });

    tearDown(() => configured.dispose());

    Future<void> agreeConfigured(String passcode) async {
      for (var i = 0; i < ScanTuning.artAgreementFrames; i++) {
        artReadings.add(ArtReading(artSeq++, HashMatch(passcode, 2)));
        await settle();
      }
      await settle();
    }

    test('a match is offered for review with the configured defaults',
        () async {
      await agreeConfigured(darkMagician);

      final s = configured.read(scanControllerProvider);
      expect(s.status, ScanStatus.matched);
      expect(s.condition, CardCondition.lightPlayed);
      expect(s.edition, CardEdition.first);
      expect(s.language, 'DE');
    });

    test('confirm writes the configured condition, edition and language',
        () async {
      await agreeConfigured(darkMagician);
      await configured.read(scanControllerProvider.notifier).confirm();
      await settle();

      final scanned = (await CollectionDao(db).getEntriesForPasscode(darkMagician))
          .where(
        (e) => e.printingId == null && e.condition == CardCondition.lightPlayed,
      );
      expect(scanned, hasLength(1));
      expect(scanned.first.edition, CardEdition.first);
      expect(scanned.first.language, 'DE');
    });
  });

  // Half of the "declining a card kills scanning" fix. [ScanPaused] is
  // `keepAlive` and this controller is its only writer, so a resolution that
  // exits without releasing the pause does not cost one frame — it stops
  // `artReadings` yielding for the rest of the process, with the camera still
  // streaming and every on-screen signal green. Each exit used to release the
  // pause by hand and three of them did not.
  //
  // The other half — the screen being torn down while a panel is up — is owned
  // by `_ScanScreenState.dispose()` and covered in `scan_screen_test.dart`,
  // because Riverpod forbids a provider writing to another provider from its
  // own `onDispose`.
  group('the pause is released on every resolution path', () {
    test('a review panel keeps the pause it was handed', () async {
      fakeCandidates = const [ArtCandidate(dmCard, 4)];
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.matched);
      expect(
        container.read(scanPausedProvider),
        isTrue,
        reason: 'the review gate is meant to freeze the pipeline — the '
            '`finally` must not undo the hand-off',
      );
    });

    test('a failing resolution resumes scanning instead of wedging it',
        () async {
      fakeMatcher = _ThrowingArtMatcher();
      await agreeArt(darkMagician);

      expect(state().status, ScanStatus.detecting);
      expect(state().artAgreementBuffer, isEmpty);
      expect(
        container.read(scanPausedProvider),
        isFalse,
        reason: 'a DB or matcher hiccup costs one run, not the session',
      );
    });

    test('a status change mid-resolution does not pin the pause', () async {
      final gate = Completer<void>();
      fakeMatcher = _GatedArtMatcher(gate, const [ArtCandidate(dmCard, 4)]);

      // Starts the resolve, which now blocks on the gate.
      await agreeArt(darkMagician);
      expect(state().status, ScanStatus.reading);

      // A frame with no card arrives while the DB round trip is in flight and
      // moves the machine on, so the resolve's `status != reading` guard will
      // discard the result. That branch used to return without un-pausing.
      await feedArt(null);
      expect(state().status, ScanStatus.detecting);

      gate.complete();
      await settle();

      expect(container.read(scanPausedProvider), isFalse);
    });

    test('a failing showBestGuesses resumes scanning', () async {
      await feedUnmatched();
      fakeMatcher = _ThrowingArtMatcher();
      await controller().showBestGuesses();
      await settle();

      expect(state().status, ScanStatus.detecting);
      expect(state().unmatchedStreak, 0);
      expect(container.read(scanPausedProvider), isFalse);
    });

    test('showBestGuesses finding nothing releases the pause', () async {
      fakeCandidates = const [];
      fakeGuesses = const [];
      await feedUnmatched();
      await controller().showBestGuesses();
      await settle();

      expect(state().status, ScanStatus.detecting);
      expect(container.read(scanPausedProvider), isFalse);
    });
  });
}
