import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/features/reader/display/colour_filter_screen.dart';
import 'package:otaku_reader/features/reader/display/reader_display.dart';
import 'package:otaku_reader/features/reader/display/reader_display_layer.dart';
import 'package:otaku_reader/features/reader/display/reader_display_settings.dart';

import 'helpers/isar_test_env.dart';

/// The reader's colour treatment: the tint, the desaturation and the dim.
///
/// Keys that were declared from the start and read by nothing, which is the
/// state `FEATURES.md` exists to catch. So the guards that matter here are the
/// ones about *reaching a surface*, not the ones about storing a value — a
/// round-trip test is exactly what would have passed the whole time these were
/// dead.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('display', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  setUp(() {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
  });

  tearDown(Get.reset);

  group('a fresh install', () {
    test('has every treatment off', () {
      // All off, unlike the tap-zone switches. A reader who has never opened
      // Settings should meet the artwork as the scanner made it.
      expect(ReaderDisplaySettings.dimEnabled, isFalse);
      expect(ReaderDisplaySettings.filterEnabled, isFalse);
      expect(ReaderDisplaySettings.greyscale, isFalse);
      expect(ReaderDisplaySettings.invert, isFalse);
      expect(ReaderDisplaySettings.background, ReaderBackground.black);
    });

    test('carries a usable tint rather than transparent black', () {
      // A default of 0 is a fully transparent black: switching the filter on
      // would change nothing and read as broken on first use.
      final colour = Color(ReaderDisplaySettings.filterColor);
      expect(colour.a, greaterThan(0));
      expect(ReaderDisplaySettings.filterBlend, ReaderBlend.srcOver);
    });
  });

  group('the blend modes', () {
    test('keep AnymeX\'s order, because the index is what is stored', () {
      // Re-ordering these to something tidier silently re-points every stored
      // filter. Pinned against the reference's own `_blendModeFromIndex`.
      expect(ReaderBlend.values[0].mode, BlendMode.srcOver);
      expect(ReaderBlend.values[1].mode, BlendMode.multiply);
      expect(ReaderBlend.values[15].mode, BlendMode.luminosity);
      expect(ReaderBlend.values, hasLength(16));
    });

    test('an index from a newer build falls back rather than throwing', () {
      // Read on the way into the reader, so a range error is a chapter that
      // will not open.
      expect(ReaderBlend.fromIndex(99), ReaderBlend.srcOver);
      expect(ReaderBlend.fromIndex(-1), ReaderBlend.srcOver);
    });

    test('every mode has a distinct label', () {
      expect(
        ReaderBlend.values.map((b) => b.label).toSet(),
        hasLength(ReaderBlend.values.length),
      );
    });
  });

  group('the stored background', () {
    test('clamps through the enum rather than a literal', () {
      // The `int status = 5` row: an out-of-range index must not index past
      // the end, and the clamp must follow the enum when it grows.
      ReaderKeys.readerTheme.set<int>(99);
      expect(ReaderDisplaySettings.background, ReaderBackground.values.last);
      ReaderKeys.readerTheme.set<int>(-3);
      expect(ReaderDisplaySettings.background, ReaderBackground.values.first);
    });

    test('every member round-trips', () {
      for (final b in ReaderBackground.values) {
        ReaderDisplaySettings.setBackground(b);
        expect(ReaderDisplaySettings.background, b, reason: b.name);
      }
    });
  });

  group('the dim', () {
    test('is a positive magnitude, clamped to its own maximum', () {
      ReaderDisplaySettings.setDim(200);
      expect(ReaderDisplaySettings.dim, ReaderDisplaySettings.maxDim);
      ReaderDisplaySettings.setDim(-40);
      expect(ReaderDisplaySettings.dim, 0);
    });

    test('keeps its magnitude across a toggle', () {
      // Two keys rather than "zero means off": collapsing them loses the
      // setting every time the switch is used.
      ReaderDisplaySettings.setDim(40);
      ReaderDisplaySettings.setDimEnabled(true);
      ReaderDisplaySettings.setDimEnabled(false);
      ReaderDisplaySettings.setDimEnabled(true);
      expect(ReaderDisplaySettings.dim, 40);
    });

    testWidgets('renders nothing at zero rather than a transparent box', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: ReaderDimVeil(percent: 0)),
      );
      // The same rule as a zero-sigma `BackdropFilter`: at zero, remove the
      // effect rather than scale it to zero.
      //
      // Scoped to the veil's own subtree. A bare `find.byType(ColoredBox)`
      // matches a **transparent** one that `MaterialApp` renders on its own, so
      // the unscoped version fails against the harness rather than the widget
      // -- which is the defect this file's neighbours keep recording, arriving
      // in the test that was written to check for it.
      expect(
        find.descendant(
          of: find.byType(ReaderDimVeil),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ReaderDimVeil),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    testWidgets('paints black at the stored fraction', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ReaderDimVeil(percent: 40)),
      );
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(0.4, 1e-9),
      );
    });
  });

  group('the display layer', () {
    Future<void> pump(WidgetTester tester, ReaderDisplayLayer layer) =>
        tester.pumpWidget(MaterialApp(home: layer));

    const child = SizedBox.shrink();

    testWidgets('adds nothing when everything is off', (tester) async {
      await pump(tester, const ReaderDisplayLayer(child: child));
      // A `ColorFiltered` is not free — it allocates a layer — so "no
      // treatment" has to mean no widget, not an identity filter.
      expect(find.byType(ColorFiltered), findsNothing);
    });

    testWidgets('greyscale and invert compose', (tester) async {
      // The correction to AnymeX, whose reader reads
      // `if (greyscale) ... else if (invert)` -- so turning greyscale on leaves
      // a live invert switch doing nothing. Mutating this back to exclusive
      // has to fail here.
      await pump(
        tester,
        const ReaderDisplayLayer(greyscale: true, invert: true, child: child),
      );
      expect(find.byType(ColorFiltered), findsNWidgets(2));
    });

    testWidgets('the tint is applied once, not twice', (tester) async {
      // AnymeX applies its filter through two mechanisms that are both
      // unconditionally in the same `Stack` -- a `ColorFiltered` on the content
      // and a `CustomPaint` overlay drawing the same colour in the same blend
      // mode over the top.
      await pump(
        tester,
        const ReaderDisplayLayer(
          filter: Color(0x80FF0000),
          blend: ReaderBlend.multiply,
          child: child,
        ),
      );
      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('tints last, so the tint survives a desaturation', (
      tester,
    ) async {
      // Order is the one thing that can make this control silently inert:
      // tinting first and then desaturating throws the tint away.
      await pump(
        tester,
        const ReaderDisplayLayer(
          greyscale: true,
          filter: Color(0x80FF0000),
          child: child,
        ),
      );
      final filters = tester
          .widgetList<ColorFiltered>(find.byType(ColorFiltered))
          .toList();
      expect(filters, hasLength(2));
      // The outermost is first in a depth-first walk, and the outermost is the
      // one applied last to the pixels beneath it.
      expect(
        filters.first.colorFilter,
        const ColorFilter.mode(Color(0x80FF0000), BlendMode.srcOver),
      );
    });
  });

  group('the colour filter screen', () {
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
          // `copyWith` off the real data -- a fresh `MediaQueryData` carries
          // `size: Size.zero`, which this repo has already shipped a green
          // suite against.
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: const ColourFilterScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a channel slider writes only its own byte', (tester) async {
      ReaderDisplaySettings.setFilterEnabled(true);
      ReaderDisplaySettings.setFilterColor(0x40FFB000);
      await open(tester);

      final red = find.byType(Slider).first;
      await tester.ensureVisible(red);
      await tester.pumpAndSettle();
      await tester.drag(red, const Offset(-200, 0));
      await tester.pumpAndSettle();

      final stored = ReaderDisplaySettings.filterColor;
      expect((stored >> 16) & 0xFF, lessThan(0xFF), reason: 'red moved');
      // The shift arithmetic is where a packed colour goes wrong silently:
      // a mask that is off by a byte edits a neighbour and nothing throws.
      expect((stored >> 24) & 0xFF, 0x40, reason: 'alpha untouched');
      expect((stored >> 8) & 0xFF, 0xB0, reason: 'green untouched');
      expect(stored & 0xFF, 0x00, reason: 'blue untouched');
    });

    testWidgets('picking a blend mode stores it', (tester) async {
      ReaderDisplaySettings.setFilterEnabled(true);
      await open(tester);

      final target = find.text(ReaderBlend.multiply.label);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(ReaderDisplaySettings.filterBlend, ReaderBlend.multiply);
    });

    testWidgets('the preview carries the live tint', (tester) async {
      ReaderDisplaySettings.setFilterEnabled(true);
      ReaderDisplaySettings.setFilterColor(0x80FF0000);
      ReaderDisplaySettings.setFilterBlend(ReaderBlend.multiply);
      await open(tester);

      // A preview that does not move with the sliders is decoration, and this
      // screen's whole argument for existing is that sixteen blend modes are
      // not something anyone can hold in their head.
      final layer = tester.widget<ReaderDisplayLayer>(
        find.byType(ReaderDisplayLayer),
      );
      expect(layer.filter, const Color(0x80FF0000));
      expect(layer.blend, ReaderBlend.multiply);
    });

    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('fits at ${width.toInt()}px', (tester) async {
        await open(tester, size: Size(width, 900));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('fits at a doubled system font', (tester) async {
      await open(tester, size: const Size(320, 900), textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
