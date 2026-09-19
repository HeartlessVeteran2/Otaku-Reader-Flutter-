import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/more/screens/about_screen.dart';

/// About, on the chrome vocabulary.
///
/// It was in `one_ui_test.dart`'s screen matrix and is not any more: a
/// converted screen still builds a `CustomScrollView` inside
/// `ChromeScaffold.slivers`, so it kept passing a group whose own docstring
/// had stopped being true of it. These are the assertions that are actually
/// about this screen.
void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const AboutScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('the hero card and both sections render', (tester) async {
    await open(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Otaku Reader'), findsOneWidget);
    expect(find.text('This app'), findsOneWidget);
    expect(find.text('Built on'), findsOneWidget);
    for (final row in const [
      'Source code',
      'Report a problem',
      'Open-source licences',
      'Mangayomi extensions',
      'AniList',
    ]) {
      expect(find.text(row), findsOneWidget, reason: '"$row" is missing');
    }
  });

  group('nothing lands under the header pill, at every phone width', () {
    // The ninth recorded instance of analyze being blind to layout was exactly
    // this: a body read the header scope from the wrong context, took the
    // documented zero fallback, and drew its first element behind a blurred
    // pill -- which reads as a flourish rather than as a control nobody can
    // press. `ChromeScaffold.slivers` inserts the gap itself, so this asserts
    // that the screen did not defeat it.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await open(tester, size: Size(width, 900));

        final header = tester.getRect(find.byType(PillHeader));
        expect(
          tester.getRect(find.byType(ChromeCard).first).top,
          greaterThanOrEqualTo(header.bottom),
          reason: 'the hero card is under the header at ${width.toInt()}px',
        );
      });
    }
  });

  testWidgets('a doubled system font neither clips nor overflows', (
    tester,
  ) async {
    // The hero card's height is entirely text, which is the one shape where a
    // large accessibility font is a layout change rather than a cosmetic one.
    await tester.binding.setSurfaceSize(const Size(320, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(const AboutScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('every row does something on tap', (tester) async {
    // `onOpen: (_) {}` -- live UI wired to nothing -- is a row in this
    // project's own mistakes table, and it analysed clean and looked finished.
    await open(tester);

    final tiles = tester.widgetList<ChromeTile>(find.byType(ChromeTile));
    expect(tiles, hasLength(5));
    for (final tile in tiles) {
      expect(tile.onTap, isNotNull, reason: '"${tile.title}" does nothing');
    }
  });
}
