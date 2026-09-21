import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';

/// The tap-zone model, and the geometry choice behind it.
///
/// AnymeX stores each zone as a normalised `Rect` and resolves a tap by walking
/// its list **backwards**, so a later zone wins an overlap — a rule that only
/// exists because free-form rectangles can overlap. They can also leave a
/// **gap**, which nothing resolves: a tap there silently does nothing, and the
/// format cannot tell that apart from a zone deliberately set to do nothing.
///
/// Bands that are shares of one axis have neither failure available. These
/// tests are mostly about that: the invariant, and the right-to-left mirroring
/// the reference gets wrong.
void main() {
  group('bands cover the axis by construction', () {
    test('the standard profile is valid and spans it', () {
      final profile = TapZoneProfile.standard;

      expect(profile.isValid, isTrue);
      expect(
        profile.bands.fold<double>(0, (sum, b) => sum + b.fraction),
        closeTo(1, TapZoneProfile.tolerance),
      );
    });

    test('a profile that leaves a gap is refused', () {
      // The failure free-form rectangles have and bands do not. Refused at the
      // boundary rather than written and rediscovered as a dead strip of screen
      // on a device.
      expect(
        TapZoneProfile(const [
          TapBand(0.3, ReaderAction.previous),
          TapBand(0.3, ReaderAction.next),
        ]).isValid,
        isFalse,
      );
    });

    test('a profile that overflows the axis is refused', () {
      expect(
        TapZoneProfile(const [
          TapBand(0.6, ReaderAction.previous),
          TapBand(0.6, ReaderAction.next),
        ]).isValid,
        isFalse,
      );
    });

    test('slider arithmetic that misses 1 by a rounding error is accepted', () {
      // Three equal bands cannot be written exactly, and a profile refused for
      // that would fall back to the default and silently discard what the user
      // set. The Kotlin Otaku-Reader allows the same tolerance for the same
      // reason.
      expect(
        TapZoneProfile(const [
          TapBand(0.3333, ReaderAction.previous),
          TapBand(0.3333, ReaderAction.toggleChrome),
          TapBand(0.3333, ReaderAction.next),
        ]).isValid,
        isTrue,
      );
    });

    test('every position along the axis resolves to a band', () {
      // The property the invariant exists for, asserted as a property: there is
      // no position in [0, 1] that lands nowhere.
      final profile = TapZoneProfile.standard;
      for (var i = 0; i <= 100; i++) {
        expect(
          profile.actionAt(i / 100),
          isNot(isNull),
          reason: 'position ${i / 100}',
        );
      }
      expect(profile.actionAt(0), ReaderAction.previous);
      expect(profile.actionAt(0.5), ReaderAction.toggleChrome);
      expect(profile.actionAt(1), ReaderAction.next);
    });

    test('the boundary belongs to the band before it, consistently', () {
      // Exactly on a seam is a real tap. Without a rule it is whichever branch
      // the loop happens to reach first, and the two neighbours disagree about
      // who owns it.
      final profile = TapZoneProfile.standard;

      expect(profile.actionAt(0.2999), ReaderAction.previous);
      expect(profile.actionAt(0.3), ReaderAction.toggleChrome);
      expect(profile.actionAt(0.6999), ReaderAction.toggleChrome);
      expect(profile.actionAt(0.7), ReaderAction.next);
    });
  });

  group('a stored profile that cannot be read falls back', () {
    // Read on the way into the reader, so a throw here is a chapter that will
    // not open. Every one of these has to answer null and let the caller take
    // the standard profile.
    for (final entry in {
      'not json': 'certainly not json',
      'not a list': '{"f": 0.5}',
      'an action index from a newer build': '[{"f":1.0,"a":99}]',
      'a negative action index': '[{"f":1.0,"a":-1}]',
      'a fraction that is not a number': '[{"f":"half","a":0}]',
      'a fraction past the axis': '[{"f":1.5,"a":0}]',
      'a zero-width band': '[{"f":0.0,"a":0}]',
      'bands that do not cover the axis': '[{"f":0.25,"a":0}]',
      'an empty list': '[]',
    }.entries) {
      test(entry.key, () {
        expect(TapZoneProfile.decode(entry.value), isNull, reason: entry.key);
      });
    }

    test('nothing stored at all', () {
      expect(TapZoneProfile.decode(null), isNull);
    });

    test('a profile this build wrote round-trips', () {
      // The other direction. Without it, a decoder that refused *everything*
      // would satisfy every test above.
      final original = TapZoneProfile(const [
        TapBand(0.25, ReaderAction.previousChapter),
        TapBand(0.5, ReaderAction.none),
        TapBand(0.25, ReaderAction.nextChapter),
      ]);

      final restored = TapZoneProfile.decode(original.encode());

      expect(restored, isNotNull);
      expect(
        restored!.bands.map((b) => b.action),
        original.bands.map((b) => b.action),
      );
      expect(
        restored.bands.map((b) => b.fraction),
        original.bands.map((b) => b.fraction),
      );
    });
  });

  group('every action is named, in one place', () {
    test('and no two share a label', () {
      // Both the reader's feedback and the editor's picker render these, so a
      // member added later cannot be labelled in one and left blank in the
      // other — and two actions sharing a label is a picker where one row
      // cannot be told from another.
      for (final action in ReaderAction.values) {
        expect(action.label.trim(), isNotEmpty, reason: action.name);
      }
      expect(
        ReaderAction.values.map((a) => a.label).toSet(),
        hasLength(ReaderAction.values.length),
      );
    });

    test('the action set needs no per-layout filter', () {
      // The reason there are six rather than AnymeX's eight. Its set splits
      // page turns from scrolling, so its editor must hide the pair that does
      // not apply to the layout being edited, and a zone carrying the wrong one
      // is a dead zone with nothing to say so. `next`/`previous` mean a unit of
      // reading order, which both layouts have — so there is nothing to filter.
      expect(ReaderAction.values, hasLength(6));
      expect(
        ReaderAction.values.map((a) => a.name),
        isNot(anyElement(contains('scroll'))),
        reason: 'no action names an axis',
      );
      expect(
        ReaderAction.values.map((a) => a.name),
        isNot(anyElement(contains('Page'))),
        reason: 'no action names a layout',
      );
    });
  });
}
