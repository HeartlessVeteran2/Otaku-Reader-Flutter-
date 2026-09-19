import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/more/screens/more_screen.dart';

/// The More hub on AnymeX's feature-card shape.
///
/// Every test here is about something `flutter analyze` cannot see. Two
/// specific failures are being prevented, and both have shipped in this
/// vocabulary before:
///
/// - a body that starts *under* the blurred pill, because the header scope was
///   read from the wrong side of the widget that publishes it;
/// - a card whose description is clipped on a narrow phone, because the row
///   was given a fixed height instead of an intrinsic one.
void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  const destinations = <String>['History', 'Downloads', 'Settings', 'About'];

  group('the cards start below the header, at every phone width', () {
    // ChromeHeaderScope answers 0 when there is no header above it, which is
    // right for a row dropped into a sheet and silently wrong for a screen
    // that reads it from its own State's context. That is the ninth recorded
    // instance of analyze being blind to layout, and it rendered the first
    // row behind a translucent pill -- which reads as a flourish, not as a
    // control nobody can press.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(host(const MoreScreen()));
        await tester.pumpAndSettle();

        final header = tester.getRect(find.byType(PillHeader));
        // The CARD's top, not the title text's. The text sits about 76px down
        // inside the card, behind the icon tile -- so asserting the text
        // clears the header still passes with the whole card slid up under
        // it, which is precisely the defect. Measured: with the scope read
        // from the wrong context the cards start at y=8 and every title still
        // lands below the pill.
        for (final card
            in find.byType(ChromeFeatureCard).evaluate().map((e) => e.widget)) {
          expect(
            tester.getRect(find.byWidget(card)).top,
            greaterThanOrEqualTo(header.bottom),
            reason: 'a card is under the header pill at ${width.toInt()}px',
          );
        }
        for (final name in destinations) {
          expect(find.text(name), findsOneWidget);
        }
      });
    }
  });

  group('no card is clipped or overflows, at every phone width', () {
    // The star row overflowed a 320px phone by 89 pixels with analyze clean
    // (seventh instance). A two-up row of cards whose descriptions wrap
    // differently per width is the same shape of risk.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(host(const MoreScreen()));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final card in tester.widgetList<ChromeFeatureCard>(
          find.byType(ChromeFeatureCard),
        )) {
          final rect = tester.getRect(find.byWidget(card));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
      });
    }
  });

  // The state a fixed height cannot reach. At the default text scale a
  // hardcoded 150px happens to fit the tallest card at 320px -- measured, and
  // it is why a fixed-height mutation passes every other test here. Doubling
  // the system font is the ordinary accessibility setting that ends that, and
  // a card is one of the few things in this app whose height is entirely text.
  testWidgets('a doubled system font does not clip or overflow a card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(const MoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('paired cards are the same height', (tester) async {
    // IntrinsicHeight, not a fixed height: a fixed one clips the taller
    // description on a narrow phone and says nothing about it. Asserting the
    // pair matches is what a fixed height would also satisfy -- so the
    // narrow-width group above is what actually catches the clip, and this
    // asserts the alignment the stretch is *for*.
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(const MoreScreen()));
    await tester.pumpAndSettle();

    final heights = tester
        .widgetList<ChromeFeatureCard>(find.byType(ChromeFeatureCard))
        .map((c) => tester.getRect(find.byWidget(c)).height)
        .toList();

    expect(heights, hasLength(4));
    expect(heights[0], heights[1]);
    expect(heights[2], heights[3]);
  });

  testWidgets('every destination is rendered and tappable', (tester) async {
    // A hub whose card does nothing on tap is the `onOpen: (_) {}` row in this
    // project's own mistakes table: live UI wired to nothing, analysing clean.
    await tester.pumpWidget(host(const MoreScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ChromeFeatureCard), findsNWidgets(4));
    for (final name in destinations) {
      expect(find.text(name), findsOneWidget);
      final card = find.ancestor(
        of: find.text(name),
        matching: find.byType(ChromeFeatureCard),
      );
      expect(tester.widget<ChromeFeatureCard>(card).onTap, isNotNull);
    }
  });
}
