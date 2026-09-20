import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// Every word of every card is on screen.
  ///
  /// `takeException()` is blind to this: an ellipsis overflow throws nothing,
  /// it just silently drops the end of the sentence. `didExceedMaxLines` is
  /// the question actually being asked -- *was anything hidden* -- and it is
  /// the assertion the first version of this suite should have made.
  ///
  /// Note the widget-test font makes every glyph a full em square, so text
  /// here is roughly twice the width it is on a device. That makes this
  /// assertion strictly *harder* to satisfy than reality, which is the right
  /// direction for a guard to err in.
  void expectNothingHidden(WidgetTester tester) {
    for (final destination in <String>[
      ...destinations,
      'What you have read, newest first',
      'The queue, and what it is using on disk',
      'Appearance, reader defaults, sources',
      'Version, licences and credits',
    ]) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(destination))
            .didExceedMaxLines,
        isFalse,
        reason: '"$destination" is truncated',
      );
    }
  }

  testWidgets('no card hides a word of its label or its sentence', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(const MoreScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expectNothingHidden(tester);
  });

  testWidgets('nor at a doubled system font', (tester) async {
    // A card's height is almost entirely text, so a large accessibility font
    // is a layout change here rather than a cosmetic one -- and the reader who
    // enlarged the font is exactly the one a cap would hide the sentence from.
    await tester.binding.setSurfaceSize(const Size(320, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(const MoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expectNothingHidden(tester);
  });

  testWidgets('it scrolls, and the cards pass under the header', (
    tester,
  ) async {
    // The scroll coverage More lost when it left `one_ui_test`'s matrix, with
    // the hole that file's own docstring warns about closed: on a screen whose
    // content fits, `maxScrollExtent` is 0 and a drag asserts *nothing*.
    // Measured, More at 400x800 is exactly that case. So the extent is
    // asserted first, and the doubled font is what guarantees one.
    await tester.binding.setSurfaceSize(const Size(320, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(const MoreScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'nothing to scroll -- the drag below would prove nothing',
    );

    final before = tester.getRect(find.byType(ChromeFeatureCard).first).top;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(position.pixels, greaterThan(0));
    expect(
      tester.getRect(find.byType(ChromeFeatureCard).first).top,
      lessThan(before),
      reason: 'the content did not actually move',
    );
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
