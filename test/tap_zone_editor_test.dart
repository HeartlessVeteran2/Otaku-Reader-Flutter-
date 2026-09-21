import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_editor_screen.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';

import 'helpers/isar_test_env.dart';

/// The screen that authors the bands the reader resolves taps against.
///
/// The three guards that carry the most weight here are not about pixels:
///
/// - **The selector must write no reader state.** AnymeX persists the flags its
///   equivalent controls set, and its *reader* then reads them — so looking at
///   the "Paged" tab changes how a webtoon chapter behaves. Mutating this
///   screen back to that has to fail a test.
/// - **The preview must mirror when the reader will.** A preview that always
///   draws left-to-right shows the opposite of the reader's behaviour for every
///   right-to-left manga, and each file stays self-consistent while it does.
/// - **A slider must write.** This repo has shipped three controls wired to
///   nothing, and every one of them round-tripped its key perfectly.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async => env = await IsarTestEnv.open(
      'tap-zone-editor',
      db.AppDatabaseSchemas.all,
    ),
  );
  tearDownAll(() async => env?.close());

  setUp(() {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
  });

  tearDown(Get.reset);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        // `copyWith` off the real data, never a fresh `MediaQueryData()`. A
        // fresh one carries `size: Size.zero`, which every read of
        // `MediaQuery.sizeOf` then believes -- so the preview's height cap came
        // out at zero and the bands all collapsed onto the same point. The
        // width tests below were passing against a preview that was not there.
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: const TapZoneEditorScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The bands as they are *painted*, leading edge first along [axis].
  List<String> painted(WidgetTester tester, {Axis axis = Axis.horizontal}) {
    final labels = <(double, String)>[];
    for (final action in ReaderAction.values) {
      for (final element
          in find
              .descendant(
                of: find.byType(AspectRatio),
                matching: find.text(action.label),
              )
              .evaluate()) {
        final centre = tester.getCenter(find.byWidget(element.widget));
        labels.add((
          axis == Axis.horizontal ? centre.dx : centre.dy,
          action.label,
        ));
      }
    }
    labels.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final l in labels) l.$2];
  }

  group('the layout selector', () {
    testWidgets('switches which profile is edited', (tester) async {
      // Two different profiles, so "which one is on screen" is answerable.
      TapZoneSettings.setProfileFor(
        ReadingLayout.webtoon,
        TapZoneProfile.standard.withActionAt(1, ReaderAction.nextChapter),
      );
      await open(tester);

      expect(find.text('Show or hide the controls'), findsWidgets);

      await tester.tap(find.text('Continuous'));
      await tester.pumpAndSettle();

      expect(find.text('Next chapter'), findsWidgets);
    });

    testWidgets('writes no reader state', (tester) async {
      await open(tester);
      await tester.tap(find.text('Continuous'));
      await tester.pumpAndSettle();

      // AnymeX's bug, pinned. Its settings screen persists `activeTapIsWebtoon`
      // and the reader reads it, so the profile in force is the one last
      // *looked at* rather than the one being *read in*. Here the selector is
      // screen-local: the reader picks from its own layout, and nothing this
      // screen does can change which layout that is.
      expect(ReaderKeys.readingLayout.get<Object?>(), isNull);
      expect(ReaderKeys.readingDirection.get<Object?>(), isNull);
      expect(ReaderKeys.webtoonDirection.get<Object?>(), isNull);
    });
  });

  group('the preview', () {
    testWidgets('draws the bands in reading order', (tester) async {
      await open(tester);
      expect(painted(tester), [
        'Previous',
        'Show or hide the controls',
        'Next',
      ]);
    });

    testWidgets('mirrors when the reader will', (tester) async {
      ReaderKeys.readingDirection.set<int>(ReadingDirection.rightToLeft.index);
      await open(tester);

      // The reader measures from the leading edge and mirrors the position, so
      // the band authored first is met on the right. A preview that ignored
      // this would show the reverse of what a tap does, for most manga.
      expect(painted(tester), [
        'Next',
        'Show or hide the controls',
        'Previous',
      ]);
    });

    testWidgets('does not mirror when mirroring is off', (tester) async {
      ReaderKeys.readingDirection.set<int>(ReadingDirection.rightToLeft.index);
      TapZoneSettings.setMirrorWhenReversed(false);
      await open(tester);

      // Both preferences are real — mirror with the text, or keep the zones
      // where a thumb learned them — so the preview follows the setting rather
      // than the direction alone.
      expect(painted(tester), [
        'Previous',
        'Show or hide the controls',
        'Next',
      ]);
    });

    testWidgets('lays the bands down the page for a vertical layout', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Continuous'));
      await tester.pumpAndSettle();

      // Continuous defaults to top-to-bottom, so the same three bands stack.
      expect(painted(tester, axis: Axis.vertical), [
        'Previous',
        'Show or hide the controls',
        'Next',
      ]);
    });

    testWidgets('tapping a band assigns its action', (tester) async {
      await open(tester);

      await tester.tap(
        find
            .descendant(
              of: find.byType(AspectRatio),
              matching: find.text('Previous'),
            )
            .first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next chapter').last);
      await tester.pumpAndSettle();

      // Stored, not merely rendered. The three dead controls this repo has
      // shipped all rendered correctly.
      final stored = TapZoneSettings.profileFor(ReadingLayout.paged);
      expect(stored.bands[0].action, ReaderAction.nextChapter);
      expect(stored.bands[0].fraction, closeTo(0.3, 1e-9));
    });
  });

  group('the boundary sliders', () {
    testWidgets('move a cut and store bands that still sum to one', (
      tester,
    ) async {
      await open(tester);
      final slider = find.byType(Slider).first;
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      await tester.drag(slider, const Offset(-60, 0));
      await tester.pumpAndSettle();

      final stored = TapZoneSettings.profileFor(ReadingLayout.paged);
      expect(
        stored.bands[0].fraction,
        lessThan(0.3),
        reason: 'the first boundary moved back',
      );
      expect(stored.isValid, isTrue);
      expect(
        stored.bands.fold<double>(0, (a, b) => a + b.fraction),
        closeTo(1, TapZoneProfile.tolerance),
      );
    });

    testWidgets('cannot author a band below the minimum', (tester) async {
      await open(tester);
      // Dragged far past the end. The slider's own bounds are what stop it, so
      // this is the assertion that a dead zone is unreachable rather than
      // merely unlikely.
      await tester.ensureVisible(find.byType(Slider).first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider).first, const Offset(-4000, 0));
      await tester.pumpAndSettle();

      final stored = TapZoneSettings.profileFor(ReadingLayout.paged);
      for (final band in stored.bands) {
        expect(band.fraction, greaterThanOrEqualTo(kMinBandFraction - 1e-9));
      }
    });

    testWidgets('one per boundary, not one per band', (tester) async {
      await open(tester);
      expect(find.byType(Slider), findsNWidgets(2));
    });

    testWidgets('step by a fixed 5% whatever room they have', (tester) async {
      // `Slider.divisions` divides that slider's own `max - min`, and these
      // bounds are dynamic -- each boundary is fenced in by its neighbours. A
      // fixed 20 divisions therefore gave the standard profile a 3% step, and
      // 2% once the other boundary moved: not merely off the documented grid
      // but not constant either. Nothing asserted the step, so five documents
      // and a 171-pair test all described a grid the editor could not reach.
      await open(tester);
      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(slider.divisions, isNotNull);
        expect(
          (slider.max - slider.min) / slider.divisions!,
          closeTo(kBandStep, 1e-9),
          reason: 'slider ${slider.min}..${slider.max}',
        );
      }
    });

    testWidgets('keep stepping by 5% after a boundary moves', (tester) async {
      // The half the first assertion cannot see: the bug changed the step as
      // the *other* boundary moved, so a guard that only reads the opening
      // state passes while the grid drifts under the user.
      await open(tester);
      final second = find.byType(Slider).last;
      await tester.ensureVisible(second);
      await tester.pumpAndSettle();
      await tester.drag(second, const Offset(-80, 0));
      await tester.pumpAndSettle();

      for (final slider in tester.widgetList<Slider>(find.byType(Slider))) {
        expect(
          (slider.max - slider.min) / slider.divisions!,
          closeTo(kBandStep, 1e-9),
        );
      }
      // And every stored cut is still on the grid.
      for (final cut in TapZoneSettings.profileFor(ReadingLayout.paged).cuts) {
        expect(
          (cut / kBandStep) - (cut / kBandStep).round(),
          closeTo(0, 1e-9),
          reason: 'cut $cut is off the 5% grid',
        );
      }
    });

    testWidgets('are on screen beside the bands they move', (tester) async {
      // The reason the preview's height is capped. Uncapped it is 636px on a
      // 390px-wide phone, which fills the screen on its own and leaves every
      // boundary slider below the fold -- so you would drag a boundary with
      // the bands it moves off screen. Removing the cap fails here.
      await open(tester, size: const Size(390, 844));

      final viewport = tester.getRect(find.byType(MaterialApp));
      final preview = tester.getRect(find.byType(AspectRatio));
      final slider = tester.getRect(find.byType(Slider).first);

      expect(preview.bottom, lessThan(viewport.bottom));
      expect(
        slider.top,
        lessThan(viewport.bottom),
        reason: 'the first boundary slider starts below the fold',
      );
    });
  });

  testWidgets('resetting restores the standard bands', (tester) async {
    TapZoneSettings.setProfileFor(
      ReadingLayout.paged,
      TapZoneProfile.standard
          .withCuts([0.1, 0.2])
          .withActionAt(0, ReaderAction.none),
    );
    await open(tester);
    expect(find.text('Nothing'), findsWidgets);

    await tester.tap(find.byTooltip('Reset to the standard bands'));
    await tester.pumpAndSettle();

    final stored = TapZoneSettings.profileFor(ReadingLayout.paged);
    expect(stored.bands[0].action, ReaderAction.previous);
    expect(stored.bands[0].fraction, closeTo(0.3, 1e-9));
  });

  testWidgets('the switch reaches the same setting the reader reads', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // One getter, two renderers. A second default declared on this screen is
    // how a switch comes to show the opposite of what the reader does, with
    // each file perfectly self-consistent.
    expect(TapZoneSettings.enabled, isFalse);
    // The preview's own guard, named by what it wraps. `IgnorePointer` is a
    // common widget -- `ChromeTile.slider` builds one per row -- so `.first`
    // asserted against whichever happened to come first in the tree, which is
    // a test that passes for a reason unrelated to its name.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.byType(AspectRatio),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((w) => w.ignoring),
      isTrue,
    );
  });

  group('fits', () {
    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await open(tester, size: Size(width, 900));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('at a doubled system font', (tester) async {
      await open(tester, size: const Size(320, 900), textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
