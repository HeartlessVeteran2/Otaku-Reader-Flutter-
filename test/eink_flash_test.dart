import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/features/reader/display/eink_flash.dart';

/// The e-ink flash.
///
/// Scoped finders throughout: `MaterialApp` renders a **transparent**
/// `ColoredBox` of its own, so `find.byType(ColoredBox)` measures the harness
/// rather than the widget — already a row in this repo's mistakes table, from
/// the test written to apply that very lesson.
Finder flashBox() => find.descendant(
  of: find.byType(EInkFlash),
  matching: find.byType(ColoredBox),
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int page,
    bool enabled = true,
    int ms = 120,
  }) => tester.pumpWidget(
    MaterialApp(
      home: EInkFlash(
        page: page,
        enabled: enabled,
        duration: Duration(milliseconds: ms),
      ),
    ),
  );

  testWidgets('does not flash on the first build', (tester) async {
    // Opening a chapter is already a full repaint. A flash there reads as the
    // app glitching on open, so `_previous` starts at the page the reader
    // opened on rather than at a sentinel.
    await pump(tester, page: 3);
    expect(flashBox(), findsNothing);
  });

  testWidgets('flashes on a page turn and clears itself', (tester) async {
    await pump(tester, page: 1);
    expect(flashBox(), findsNothing);

    await pump(tester, page: 2);
    await tester.pump();
    expect(flashBox(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(flashBox(), findsNothing, reason: 'the timer cleared it');
  });

  testWidgets('does not flash when the setting is off', (tester) async {
    await pump(tester, page: 1, enabled: false);
    await pump(tester, page: 2, enabled: false);
    await tester.pump();

    expect(flashBox(), findsNothing);
  });

  testWidgets('a zero duration renders nothing rather than a zero flash', (
    tester,
  ) async {
    // The same rule as `ChromeCard` dropping a zero-sigma `BackdropFilter` and
    // `ReaderDimVeil` at zero: remove the effect rather than scale it to zero,
    // because "too short to see" and "not there" are different bugs.
    await pump(tester, page: 1, ms: 0);
    await pump(tester, page: 2, ms: 0);
    await tester.pump();

    expect(flashBox(), findsNothing);
  });

  testWidgets('a rebuild at the same page does not re-flash', (tester) async {
    // Ghosting is caused by the frame *changing*. A flash that fires on any
    // rebuild goes off while the reader is sitting still on one panel, which
    // is the failure a timer-driven version has by construction.
    await pump(tester, page: 1);
    await pump(tester, page: 2);
    await tester.pump();
    expect(flashBox(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(flashBox(), findsNothing);

    await pump(tester, page: 2);
    await tester.pump();
    expect(flashBox(), findsNothing);
  });

  testWidgets('the flash does not swallow taps', (tester) async {
    // At 120ms a swallowed tap is a page turn the reader has to make twice.
    var taps = 0;
    Widget build(int page) => MaterialApp(
      home: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
          Positioned.fill(
            child: EInkFlash(
              page: page,
              enabled: true,
              duration: const Duration(milliseconds: 120),
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpWidget(build(2));
    await tester.pump();
    expect(flashBox(), findsOneWidget, reason: 'flashing right now');

    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1);

    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets('mounting already past page zero does not flash', (tester) async {
    // `codeant-ai` filed this as a Major: it read the reader as letting an
    // async load move `page` from 0 to a saved resume page while the flash was
    // already mounted, so opening a resumed chapter would flash with no page
    // turned. Settled by reproduction rather than by argument, because a
    // reproduction that fails may only be disproving a guess about how to
    // provoke it.
    //
    // It does not reproduce, for two independent reasons. `_afterPagesLoaded`
    // assigns `page.value` **inside** `load()`, before the `finally` clears
    // `isLoading`; and the reader's body returns a spinner while loading, so
    // the whole `Stack` — this widget with it — is not in the tree until after
    // the resume page is set. Either one alone is enough. What reaches the
    // widget is therefore a *first build* at the resume page, and
    // `didUpdateWidget` does not run on a first build.
    //
    // This asserts that last property directly, which is the part that would
    // actually have to break for the finding to become real.
    await pump(tester, page: 12);
    expect(flashBox(), findsNothing);

    await tester.pump(const Duration(milliseconds: 200));
    expect(flashBox(), findsNothing);
  });

  testWidgets('a reader closed mid-flash does not throw', (tester) async {
    // A page turn is exactly when someone backs out, and the timer outlives
    // the widget by up to its whole duration.
    await pump(tester, page: 1);
    await pump(tester, page: 2);
    await tester.pump();
    expect(flashBox(), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
  });
}
