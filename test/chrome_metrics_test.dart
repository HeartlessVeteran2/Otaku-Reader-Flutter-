import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';

import 'helpers/isar_test_env.dart';

/// AnymeX's UI multipliers, ported as a `ThemeExtension`.
///
/// The thing worth guarding is not that the numbers multiply — it is that the
/// multiplied number reaches the **painted** shape. A setting that stores 2.0
/// while every corner stays at its token is the "live UI wired to nothing"
/// defect this project has shipped three times, and it looks identical from
/// the settings screen.
void main() {
  Widget host(Widget child, {ChromeMetrics? metrics}) => MaterialApp(
    theme: ThemeData(extensions: metrics == null ? const [] : [metrics]),
    home: Scaffold(body: child),
  );

  /// The radius a `ChromeCard` actually clips itself to.
  double paintedCardRadius(WidgetTester tester) {
    final clip = tester.widget<ClipRRect>(
      find
          .descendant(
            of: find.byType(ChromeCard),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    return (clip.borderRadius as BorderRadius).topLeft.x;
  }

  testWidgets('with no extension at all, the tokens stand as declared', (
    tester,
  ) async {
    // The default every widget test gets without being told. If this drifts,
    // every layout number in every other suite drifts with it.
    await tester.pumpWidget(host(const ChromeCard(child: Text('x'))));
    await tester.pumpAndSettle();

    expect(paintedCardRadius(tester), Chrome.cardRadius);
  });

  testWidgets('a multiplier reaches the painted corner', (tester) async {
    await tester.pumpWidget(
      host(
        const ChromeCard(child: Text('x')),
        metrics: ChromeMetrics.standard.copyWith(radiusScale: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(paintedCardRadius(tester), Chrome.cardRadius * 2);
  });

  testWidgets('zero means square, not "a bit rounder"', (tester) async {
    // 0 is a real setting on all three sliders, so it has to land exactly
    // rather than clamping to some minimum nobody asked for.
    await tester.pumpWidget(
      host(
        const ChromeCard(child: Text('x')),
        metrics: ChromeMetrics.standard.copyWith(radiusScale: 0),
      ),
    );
    await tester.pumpAndSettle();

    expect(paintedCardRadius(tester), 0);
  });

  testWidgets('glow at zero draws no shadow at all', (tester) async {
    // Not a zero-blur shadow: a `BoxShadow` with no blur and no spread paints
    // a hard rectangle behind the card, which is a different decoration
    // rather than the absence of one.
    await tester.pumpWidget(
      host(
        const ChromeCard(glow: true, child: Text('x')),
        metrics: ChromeMetrics.standard.copyWith(glowScale: 0),
      ),
    );
    await tester.pumpAndSettle();

    final decorated = find.descendant(
      of: find.byType(ChromeCard),
      matching: find.byType(DecoratedBox),
    );
    expect(
      decorated,
      findsNothing,
      reason: 'the whole decoration goes, not just its blur',
    );
  });

  testWidgets('glow above zero does draw one', (tester) async {
    // The other half: without it, deleting the glow entirely would satisfy
    // the test above.
    await tester.pumpWidget(
      host(
        const ChromeCard(glow: true, child: Text('x')),
        metrics: ChromeMetrics.standard,
      ),
    );
    await tester.pumpAndSettle();

    final box = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(ChromeCard),
        matching: find.byType(DecoratedBox),
      ),
    );
    final shadows = box
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
    expect(shadows, isNotEmpty);
  });

  testWidgets('blur at zero drops the BackdropFilter rather than zeroing it', (
    tester,
  ) async {
    // A `BackdropFilter` with sigma 0 still saves and composites a layer, so
    // a reader who turned blur off would keep paying for it.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [ChromeMetrics.standard.copyWith(blurScale: 0)],
        ),
        home: const ChromeScaffold(title: 'T', body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('blur above zero keeps it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChromeScaffold(title: 'T', body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackdropFilter), findsWidgets);
  });

  test('lerp moves every multiplier, not just the first', () {
    // A `ThemeExtension` whose `lerp` forgets a field animates one number and
    // snaps the rest, which reads as a glitch rather than as a setting.
    const a = ChromeMetrics(radiusScale: 0, glowScale: 0, blurScale: 0);
    const b = ChromeMetrics(radiusScale: 2, glowScale: 4, blurScale: 6);

    final mid = a.lerp(b, 0.5);

    expect(mid.radiusScale, 1);
    expect(mid.glowScale, 2);
    expect(mid.blurScale, 3);
  });

  group('the controller is what puts the multipliers on the theme', () {
    // The link that makes this a feature rather than three stored numbers.
    // A slider that writes a key the theme never reads is the defect this
    // project has shipped three times, and it looks identical on screen.
    IsarTestEnv? env;

    setUpAll(
      () async =>
          env = await IsarTestEnv.open('metrics', db.AppDatabaseSchemas.all),
    );
    tearDownAll(() async => env?.close());
    setUp(() {
      env!.clear();
      Get.reset();
    });
    tearDown(Get.reset);

    ChromeMetrics metricsOn(ThemeController c) =>
        c.theme(Brightness.light).extension<ChromeMetrics>()!;

    test('a fresh install renders the tokens as declared', () {
      final c = ThemeController()..onInit();

      expect(metricsOn(c), ChromeMetrics.standard);
    });

    test('setting a scale reaches the theme and the stored key', () {
      final c = ThemeController()..onInit();

      c.setRadiusScale(2.5);

      expect(metricsOn(c).radiusScale, 2.5);
      expect(
        ThemeKeys.radiusScale.get<double>(1),
        2.5,
        reason: 'and survives a restart',
      );
    });

    test('a scale beyond the slider is clamped, not stored as given', () {
      // A value can arrive from a backup, a hand-edited row or an older build
      // with different bounds. An unclamped 40x radius is an app nobody can
      // read, and it would persist.
      final c = ThemeController()..onInit();

      c.setRadiusScale(40);

      expect(metricsOn(c).radiusScale, ChromeMetrics.maxRadiusScale);
      expect(
        ThemeKeys.radiusScale.get<double>(1),
        ChromeMetrics.maxRadiusScale,
      );
    });

    test('a stored scale out of range is clamped on the way in too', () {
      // Clamping only on write trusts whatever is already on disk.
      ThemeKeys.radiusScale.set<double>(99);

      final c = ThemeController()..onInit();

      expect(metricsOn(c).radiusScale, ChromeMetrics.maxRadiusScale);
    });

    test('a non-finite scale cannot reach the controller from disk', () {
      // Half of why `_clampScale` carries no `isNaN` guard: the KV tier
      // stores `jsonEncode({'val': ...})`, and `dart:convert` refuses every
      // non-finite double. There is no row to read back, so a guard on the
      // read path would be defending a state that cannot exist.
      expect(
        () => ThemeKeys.radiusScale.set<double>(double.nan),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(
        () => ThemeKeys.radiusScale.set<double>(double.infinity),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('a non-finite scale handed straight to the setter stays usable', () {
      // The other half. A slider cannot produce NaN, but `setRadiusScale` is
      // public, so the property worth pinning is the outcome rather than the
      // mechanism: whatever goes in, what reaches a radius is finite and in
      // range -- and the write does not throw on the way past `jsonEncode`.
      //
      // Measured on Dart 3.13.3, `clamp` already does this: it compares
      // through `compareTo`, whose total order sorts NaN above every double,
      // so `double.nan.clamp(0.0, 3.0)` is `3.0`, not NaN.
      final c = ThemeController()..onInit();

      c.setRadiusScale(double.nan);

      final scale = metricsOn(c).radiusScale;
      expect(scale.isFinite, isTrue);
      expect(
        scale,
        inInclusiveRange(ChromeMetrics.minScale, ChromeMetrics.maxRadiusScale),
      );
      expect(
        ThemeKeys.radiusScale.get<double>(1),
        scale,
        reason: 'the store saw a finite number, so the write did not throw',
      );
    });
  });
}
