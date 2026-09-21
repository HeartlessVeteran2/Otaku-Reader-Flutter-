import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';

import 'helpers/isar_test_env.dart';

/// The persistence tier the reader and the Settings rows both read through.
///
/// Worth its own file because the defaults live **here** rather than at either
/// call site. A Settings row that names its own default is how a switch comes
/// to show the opposite of what the reader does, with each file perfectly
/// self-consistent — which is the `ReaderDefaults` row of the mistakes table,
/// one feature over.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('tap-zones', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  group('a fresh install', () {
    test('has zones on, mirroring on and haptics on', () {
      // All three default on, which is the reference's answer for the first
      // (AnymeX) and the Kotlin app's for the other two. A default of off for
      // the mirror would ship the right-to-left bug this feature exists to
      // avoid, to everyone who never opens Settings.
      expect(TapZoneSettings.enabled, isTrue);
      expect(TapZoneSettings.mirrorWhenReversed, isTrue);
      expect(TapZoneSettings.haptics, isTrue);
    });

    test('reads the standard bands for both layouts', () {
      for (final layout in ReadingLayout.values) {
        final profile = TapZoneSettings.profileFor(layout);
        expect(profile.isValid, isTrue, reason: layout.name);
        expect(
          profile.bands.map((b) => b.action),
          TapZoneProfile.standard.bands.map((b) => b.action),
          reason: layout.name,
        );
      }
    });
  });

  group('each switch round-trips', () {
    // The write half. A getter that always answered its default would satisfy
    // the group above.
    test('zones', () {
      TapZoneSettings.setEnabled(false);
      expect(TapZoneSettings.enabled, isFalse);
      TapZoneSettings.setEnabled(true);
      expect(TapZoneSettings.enabled, isTrue);
    });

    test('mirroring', () {
      TapZoneSettings.setMirrorWhenReversed(false);
      expect(TapZoneSettings.mirrorWhenReversed, isFalse);
    });

    test('haptics', () {
      TapZoneSettings.setHaptics(false);
      expect(TapZoneSettings.haptics, isFalse);
    });

    test('and they do not read each other', () {
      // Three booleans in one store, and a copy-pasted key would make two of
      // them the same switch. Nothing else in the suite would notice.
      TapZoneSettings.setEnabled(false);
      TapZoneSettings.setMirrorWhenReversed(true);
      TapZoneSettings.setHaptics(true);

      expect(TapZoneSettings.enabled, isFalse);
      expect(TapZoneSettings.mirrorWhenReversed, isTrue);
      expect(TapZoneSettings.haptics, isTrue);
    });
  });

  group('a stored profile', () {
    final custom = TapZoneProfile(const [
      TapBand(0.5, ReaderAction.next),
      TapBand(0.5, ReaderAction.previousChapter),
    ]);

    test('reaches the layout it was stored for, and only that one', () {
      // The reason there are two keys. One value would mean editing the paged
      // bands silently rewrote the ones used down a long strip.
      ReaderKeys.tapZonesPaged.set<String>(custom.encode());

      expect(
        TapZoneSettings.profileFor(ReadingLayout.paged).bands
            .map((b) => b.action),
        [ReaderAction.next, ReaderAction.previousChapter],
      );
      expect(
        TapZoneSettings.profileFor(ReadingLayout.webtoon).bands
            .map((b) => b.action),
        TapZoneProfile.standard.bands.map((b) => b.action),
        reason: 'continuous still reads its own key',
      );
    });

    test('whose stored value is not even a string falls back', () {
      // `sourcery-ai`, and correct. `KvHelper.get` ends in `return val as T`,
      // and its two `num` re-widening guards match `T == double` and
      // `T == int` only -- so a row holding a number reached that cast as
      // `String?` and threw a `TypeError` **before** `decode` was ever called.
      // Every bit of care in the decoder sat behind a read that could not
      // survive the row.
      ReaderKeys.tapZonesPaged.set<int>(42);

      expect(
        () => TapZoneSettings.profileFor(ReadingLayout.paged),
        returnsNormally,
      );
      expect(
        TapZoneSettings.profileFor(ReadingLayout.paged).bands
            .map((b) => b.action),
        TapZoneProfile.standard.bands.map((b) => b.action),
      );
    });

    test('that this build cannot read falls back rather than throwing', () {
      // Read on the way into the reader, so a throw here is a chapter that
      // will not open. A row from a newer build is the realistic case.
      ReaderKeys.tapZonesContinuous.set<String>('[{"f":1.0,"a":99}]');

      expect(
        () => TapZoneSettings.profileFor(ReadingLayout.webtoon),
        returnsNormally,
      );
      expect(
        TapZoneSettings.profileFor(ReadingLayout.webtoon).bands
            .map((b) => b.action),
        TapZoneProfile.standard.bands.map((b) => b.action),
      );
    });
  });

  group('the write contract', () {
    test('stores a profile the editor could author', () {
      final edited = TapZoneProfile.standard
          .withCuts([0.2, 0.5])
          .withActionAt(1, ReaderAction.nextChapter);

      expect(
        TapZoneSettings.setProfileFor(ReadingLayout.paged, edited),
        isTrue,
      );

      final read = TapZoneSettings.profileFor(ReadingLayout.paged);
      expect(read.bands[0].fraction, closeTo(0.2, 1e-9));
      expect(read.bands[1].action, ReaderAction.nextChapter);
      expect(read.bands[2].fraction, closeTo(0.5, 1e-9));
    });

    test('writes one layout without touching the other', () {
      final edited = TapZoneProfile.standard.withCuts([0.1, 0.9]);
      TapZoneSettings.setProfileFor(ReadingLayout.webtoon, edited);

      expect(
        TapZoneSettings.profileFor(ReadingLayout.webtoon).bands[0].fraction,
        closeTo(0.1, 1e-9),
      );
      // Separate keys for the same reason the directions are separate: a
      // profile authored for a page turn is not the one you want down a strip,
      // and one stored value means editing either overwrites both.
      expect(
        TapZoneSettings.profileFor(ReadingLayout.paged).bands[0].fraction,
        closeTo(0.3, 1e-9),
      );
    });

    test('refuses an invalid profile and leaves the stored bands alone', () {
      final good = TapZoneProfile.standard.withCuts([0.2, 0.5]);
      TapZoneSettings.setProfileFor(ReadingLayout.paged, good);

      // Sums to 1.2. Not reachable from the editor -- the cut points make it
      // impossible -- but a restore or an imported profile is not built here.
      final bad = TapZoneProfile(const [
        TapBand(0.6, ReaderAction.previous),
        TapBand(0.6, ReaderAction.next),
      ]);
      expect(TapZoneSettings.setProfileFor(ReadingLayout.paged, bad), isFalse);

      // The half that matters. A refusal that *cleared* the row would also
      // return false, and the caller could not tell the difference -- so the
      // assertion is on what survived, not on what was returned.
      final read = TapZoneSettings.profileFor(ReadingLayout.paged);
      expect(read.bands, hasLength(3));
      expect(read.bands[0].fraction, closeTo(0.2, 1e-9));
    });

    test('resetting forgets the row rather than writing the default into it', () {
      TapZoneSettings.setProfileFor(
        ReadingLayout.paged,
        TapZoneProfile.standard.withCuts([0.1, 0.2]),
      );
      TapZoneSettings.resetProfileFor(ReadingLayout.paged);

      // Deleted, not overwritten. The two are indistinguishable today and stop
      // being so the moment the standard bands change: a user who reset theirs
      // asked for the default, not for a copy of what it was that day.
      expect(ReaderKeys.tapZonesPaged.get<Object?>(), isNull);
      expect(
        TapZoneSettings.profileFor(ReadingLayout.paged).bands[0].fraction,
        closeTo(0.3, 1e-9),
      );
    });

    test('resetting one layout leaves the other edited', () {
      final edited = TapZoneProfile.standard.withCuts([0.1, 0.2]);
      TapZoneSettings.setProfileFor(ReadingLayout.paged, edited);
      TapZoneSettings.setProfileFor(ReadingLayout.webtoon, edited);

      TapZoneSettings.resetProfileFor(ReadingLayout.paged);

      expect(
        TapZoneSettings.profileFor(ReadingLayout.webtoon).bands[0].fraction,
        closeTo(0.1, 1e-9),
      );
    });
  });
}
