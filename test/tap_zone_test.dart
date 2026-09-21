import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_editor_screen.dart';

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

    test('the boundary belongs to the band after it, consistently', () {
      // Exactly on a seam is a real tap. Without a rule it is whichever branch
      // the loop happens to reach first, and the two neighbours disagree about
      // who owns it.
      //
      // `actionAt` returns on the first band whose running edge is *past* the
      // position, so a position sitting exactly on a seam has not passed the
      // band before it and belongs to the one after — which is what the
      // assertions below have always said. The name and the comment claimed
      // the opposite for their whole life, two lines above the numbers that
      // contradict them. Caught by `codeant-ai`.
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

  group('cut points', () {
    test('are the running edges, one fewer than the bands', () {
      // 30/40/30 -> boundaries at 30% and 70%. The editor edits these, not the
      // widths, and the whole sum-to-one invariant rests on that swap.
      final cuts = TapZoneProfile.standard.cuts;
      expect(cuts, hasLength(2));
      expect(cuts[0], closeTo(0.3, 1e-9));
      expect(cuts[1], closeTo(0.7, 1e-9));
    });

    test('a single band has none', () {
      expect(
        TapZoneProfile(const [TapBand(1, ReaderAction.toggleChrome)]).cuts,
        isEmpty,
      );
    });

    test('round-trip through withCuts changes nothing', () {
      final profile = TapZoneProfile.standard;
      final same = profile.withCuts(profile.cuts);
      expect(same.isValid, isTrue);
      for (var i = 0; i < profile.bands.length; i++) {
        expect(
          same.bands[i].fraction,
          closeTo(profile.bands[i].fraction, 1e-9),
        );
        expect(same.bands[i].action, profile.bands[i].action);
      }
    });

    test('every pair the editor can author stays valid', () {
      // The measured claim the write contract rests on, asserted rather than
      // argued: over every reachable cut pair, the bands sum to 1 well inside
      // the tolerance -- 166 of the 171 exactly. So the editor structurally
      // cannot reach `setProfileFor` with a profile it refuses, and the refusal
      // path exists for restores and imports alone.
      //
      // The bounds are **derived from the editor's own constants**, not written
      // out as `i / 20`. That spelling is what let this test pass while the
      // sliders actually stepped in 3% -- it enumerated the grid the code was
      // meant to have rather than the one it had, so it agreed with the prose
      // and neither agreed with the editor. Caught by `codeant-ai` as a nitpick
      // beside the Major, and it is the same lesson one file over: when a test
      // enumerates what a feature can produce, derive it from the feature.
      // `i * kBandStep` is deliberately the **production snap's own
      // arithmetic** -- `_cutSlider` stores `(v / kBandStep).round() *
      // kBandStep` -- and it is not interchangeable with `i / steps`. Measured:
      // `6 * 0.05` is `0.30000000000000004` while `6 / 20` is `0.3`, and
      // `19 * 0.05` is `0.9500000000000001`. Enumerating with the division
      // gives 169 exact sums for a set the editor never produces; the multiply
      // gives the true 166. Do not "simplify" this -- the count moving back to
      // 169 is the tell that the test has drifted off the code again.
      final steps = (1 / kBandStep).round();
      final floor = (kMinBandFraction / kBandStep).ceil();
      var pairs = 0;
      var exact = 0;
      for (var i = floor; i <= steps - floor; i++) {
        for (var j = i + floor; j <= steps - floor; j++) {
          final cuts = [i * kBandStep, j * kBandStep];
          final profile = TapZoneProfile.standard.withCuts(cuts);
          pairs++;
          final sum = profile.bands.fold<double>(0, (a, b) => a + b.fraction);
          if (sum == 1.0) exact++;
          expect(profile.isValid, isTrue, reason: 'cuts $cuts');
          // Every band reachable, which is what a minimum band width buys: a
          // zero-width band is a dead zone, and the failure bands exist to make
          // impossible would have been handed back by the editor. The bound
          // carries a float slack on purpose: the smallest band the editor can
          // produce is `1 - 19 * 0.05`, which is `0.04999999999999993` -- under
          // `kMinBandFraction` by 7e-17, and a dead zone only to a comparison
          // that mistakes representation error for intent.
          for (final band in profile.bands) {
            expect(
              band.fraction,
              greaterThanOrEqualTo(kMinBandFraction - 1e-9),
            );
          }
        }
      }
      // Pinned rather than recomputed: a count derived the same way the loop
      // is would assert nothing. These are the numbers that were measured, and
      // they move if `kBandStep` or `kMinBandFraction` does -- which is the
      // point, because that is a re-measurement rather than a rename.
      expect(pairs, 171);
      expect(exact, 166);
    });

    test('withCuts keeps the actions in order', () {
      final moved = TapZoneProfile.standard.withCuts([0.1, 0.2]);
      expect(
        moved.bands.map((b) => b.action),
        TapZoneProfile.standard.bands.map((b) => b.action),
      );
      expect(moved.bands[0].fraction, closeTo(0.1, 1e-9));
      expect(moved.bands[1].fraction, closeTo(0.1, 1e-9));
      expect(moved.bands[2].fraction, closeTo(0.8, 1e-9));
    });

    test('withActionAt moves no boundary', () {
      final profile = TapZoneProfile.standard;
      final edited = profile.withActionAt(1, ReaderAction.nextChapter);
      expect(edited.bands[1].action, ReaderAction.nextChapter);
      expect(edited.cuts, profile.cuts);
      // The other two untouched, which is what separates this from AnymeX's
      // `_editZone` -- there the action is the *only* thing that can change.
      expect(edited.bands[0].action, profile.bands[0].action);
      expect(edited.bands[2].action, profile.bands[2].action);
    });
  });
}
