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
}
