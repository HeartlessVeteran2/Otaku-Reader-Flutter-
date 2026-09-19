import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';

/// The chrome ported from AnymeX: floating pills over the content, segmented
/// tabs that cannot overflow, card rows.
///
/// Every test here is about a property that `flutter analyze` is structurally
/// blind to — where a widget lands, how wide it is, what a gesture leaves
/// behind. See `CLAUDE.md`: analyze reporting "No issues found" on a screen
/// that could not lay out is on its eighth recorded instance.
/// How far [SegmentedTabs] lifts the selected segment. A `Transform`, so it
/// paints outside the segment's own third without taking any room.
const _selectedScale = 1.03;

void main() {
  Widget host(Widget child) => MaterialApp(home: child);

  /// A screen whose first row is keyed, so its position can be compared with
  /// where the header actually ends.
  Widget screen({
    String title = 'Library',
    String? subtitle,
    PreferredSizeWidget? bottom,
    int rows = 40,
    bool enableSearch = false,
    TextEditingController? controller,
    ValueChanged<String>? onChanged,
    List<Widget>? actions,
  }) => ChromeScaffold.slivers(
    title: title,
    subtitle: subtitle,
    bottom: bottom,
    actions: actions,
    enableSearch: enableSearch,
    searchController: controller,
    onSearchChanged: onChanged,
    slivers: [
      SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, i) => SizedBox(
          key: ValueKey('row-$i'),
          height: 56,
          child: Text('Row $i'),
        ),
      ),
    ],
  );

  group('the body starts below the pills and scrolls under them', () {
    // The failure this prevents is invisible rather than loud: a first row
    // behind a translucent, blurred pill reads as a design flourish, not as a
    // row you cannot press. It is also the one thing a caller can forget,
    // which is why `ChromeScaffold.slivers` inserts the gap itself.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(host(screen()));
        await tester.pumpAndSettle();

        final header = tester.getRect(find.byType(PillHeader));
        final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
        expect(
          firstRow.top,
          greaterThanOrEqualTo(header.bottom),
          reason: 'the first row is under the header, not below it',
        );
      });
    }

    testWidgets('at a doubled system font size', (tester) async {
      // AnymeX hardcodes 64 (80 with a subtitle). The title grows with the
      // system font and a constant does not, so the arithmetic is wrong for
      // exactly the users who most need to read it.
      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: screen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(PillHeader));
      final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(firstRow.top, greaterThanOrEqualTo(header.bottom));
    });

    testWidgets('while searching at a doubled system font size', (
      tester,
    ) async {
      // The state the estimate cannot reach. The search pill holds a
      // `TextField`, whose height is the framework's arithmetic rather than
      // ours, and at a large font size it outgrows the title row the estimate
      // was computed from. Nothing else here fails if the scaffold stops
      // measuring and trusts the estimate — this is the case that does.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: screen(
              enableSearch: true,
              controller: controller,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(PillHeader));
      final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(firstRow.top, greaterThanOrEqualTo(header.bottom));
    });

    testWidgets('with a subtitle, which makes the title pill taller', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen(subtitle: '12 sources')));
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(PillHeader));
      final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(firstRow.top, greaterThanOrEqualTo(header.bottom));
    });

    testWidgets('with a tab bar pinned under the pills', (tester) async {
      await tester.pumpWidget(
        host(
          screen(
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(Chrome.tabBarHeight),
              child: SegmentedTabs(
                tabs: const [Text('A'), Text('B')],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(PillHeader));
      final firstRow = tester.getRect(find.byKey(const ValueKey('row-0')));
      expect(firstRow.top, greaterThanOrEqualTo(header.bottom));
    });

    testWidgets('and then scrolls under them rather than stopping short', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();

      // Down far enough to move the list, then back up so the header is on
      // screen to be scrolled under. A body merely padded down by the header
      // height would leave the band above its first row permanently empty
      // instead, which is what this asserts against.
      await tester.drag(find.text('Row 5'), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
      await tester.pumpAndSettle();

      final header = tester.getRect(find.byType(PillHeader));
      expect(header.top, 0, reason: 'the header came back for this');
      final rows = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('row-'),
            ),
          )
          .map((w) => tester.getRect(find.byKey(w.key!)));
      expect(
        rows.any((r) => r.top < header.bottom && r.bottom > header.top),
        isTrue,
        reason: 'no row is behind the header, so nothing scrolls under it',
      );
    });
  });

  testWidgets('the header is the same height whatever a caller puts in it', (
    tester,
  ) async {
    // Material's `IconButton` carries a 48px minimum, 8 more than the box the
    // header gives an action. Left to itself it makes the pill taller than the
    // title beside it — and makes the header's height a property of the call
    // site, which is not something the header can know or a screen should have
    // to think about.
    Future<double> heightWith(List<Widget> actions) async {
      await tester.pumpWidget(host(screen(actions: actions)));
      await tester.pumpAndSettle();
      return tester.getRect(find.byType(PillHeader)).height;
    }

    final bare = await heightWith([
      IconButton(onPressed: () {}, icon: const Icon(Icons.sort)),
    ]);
    final plain = await heightWith([const Icon(Icons.sort, size: 20)]);
    expect(bare, plain);
  });

  group('a header action', () {
    // The pill gives each action a fixed box, so that box is the touch target:
    // two actions sit flush and the pill's 4px padding is outside their hit
    // areas, adding nothing to the one in the middle.
    //
    // Measured **on screen** rather than on the render box. Those are the same
    // number for an action that fits and different for one that does not, and
    // the finger only ever meets the first — a raw-size assertion passes at
    // 112 for a control the user sees at 48.
    Future<void> pumpWith(WidgetTester tester, List<Widget> actions) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          screen(
            enableSearch: true,
            controller: controller,
            onChanged: (_) {},
            actions: actions,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Rect onScreen(WidgetTester tester, String tooltip) => tester.getRect(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );

    testWidgets('is a full-size touch target', (tester) async {
      await pumpWith(tester, [
        IconButton(
          onPressed: () {},
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
        ),
        PopupMenuButton<int>(tooltip: 'More', itemBuilder: (_) => const []),
      ]);

      for (final tooltip in ['Search', 'Sort', 'More']) {
        final size = onScreen(tester, tooltip).size;
        expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
      }
    });

    testWidgets('too big for its slot is scaled, never erased', (tester) async {
      // What this replaces was silent: the slot's tight constraints left a
      // 64px icon behind 24px of padding exactly **0x0** of room, so the
      // control rendered as a 48x48 nothing. No exception, no overflow
      // stripe, and `flutter analyze` clean — the failure mode this app has
      // recorded eight times before and could not see.
      await pumpWith(tester, [
        IconButton(
          onPressed: () {},
          tooltip: 'Sort',
          iconSize: 64,
          padding: const EdgeInsets.all(24),
          icon: const Icon(Icons.sort),
        ),
      ]);

      expect(tester.takeException(), isNull);
      final icon = tester.getRect(find.byIcon(Icons.sort));
      expect(
        icon.width,
        greaterThan(0),
        reason: 'the action rendered as an invisible button',
      );
      // Still bounded by the slot, so the header keeps its own height.
      final button = onScreen(tester, 'Sort');
      expect(button.width, Chrome.actionSize);
      expect(button.height, Chrome.actionSize);
    });
  });

  group('the header hides on the way down and comes back on the way up', () {
    testWidgets('a scroll down past the threshold sends it off screen', (
      tester,
    ) async {
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PillHeader)).top, 0);

      await tester.drag(find.text('Row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(PillHeader)).bottom, lessThan(0));
    });

    testWidgets('a scroll back up brings it straight back', (tester) async {
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Row 5'), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(PillHeader)).top, 0);
    });

    testWidgets('a short reversal still brings it back after scrolling on', (
      tester,
    ) async {
      // The measurement runs from where the finger last was, not from where
      // the header last moved. Those diverge as soon as the user carries on
      // scrolling *without* crossing the threshold again -- the second drag
      // here -- and anchoring on the crossing instead leaves the baseline
      // behind, so the reversal needed grows with however far past it they
      // went. That is what this was ported as, and it reads as a header that
      // has stopped answering.
      //
      // The middle drag is the whole test: without it both versions pass,
      // because a drag that ends past the threshold commits its own end as
      // the baseline.
      await tester.pumpWidget(host(screen(rows: 200)));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Row 5'), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PillHeader)).bottom, lessThan(0));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(PillHeader)).top,
        0,
        reason: 'a 60px reversal is past the threshold and was ignored',
      );
    });

    // Driven as a stream of small notifications rather than one `drag`, which
    // delivers about two. The worry this answers is that the anchor might be
    // reset by an ordinary sub-threshold update during a reversal, making the
    // distance needed depend on how the platform chunks a gesture. It is not:
    // the anchor moves only while the scroll continues the way the header has
    // already answered, so a reversal is always measured from the turn.
    //
    // Measured, the header returns at the first update past 50px — 51, 55, 60
    // and 60 for 3, 5, 15 and 60px chunks, which is `ceil(51 / chunk) * chunk`
    // and nothing else. Chunking sets the granularity, never the baseline.
    for (final chunk in <double>[3, 5, 15, 60]) {
      testWidgets('returns after ~50px delivered in ${chunk.toInt()}px steps', (
        tester,
      ) async {
        await tester.pumpWidget(host(screen(rows: 300)));
        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(200, 400));
        await gesture.moveBy(const Offset(0, -20));
        for (var i = 0; i < 40; i++) {
          await gesture.moveBy(const Offset(0, -15));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          tester.getRect(find.byType(PillHeader)).bottom,
          lessThan(0),
          reason: 'the header never hid, so the reversal proves nothing',
        );

        var reversed = 0.0;
        double? returnedAfter;
        for (var i = 0; i < 40 && returnedAfter == null; i++) {
          await gesture.moveBy(Offset(0, chunk));
          await tester.pump();
          reversed += chunk;
          await tester.pump(const Duration(milliseconds: 600));
          if (tester.getRect(find.byType(PillHeader)).top >= 0) {
            returnedAfter = reversed;
          }
        }
        await gesture.up();
        await tester.pumpAndSettle();

        expect(returnedAfter, isNotNull, reason: 'the header never came back');
        // The first step past the threshold, whatever the step size.
        expect(returnedAfter, lessThanOrEqualTo(51 + chunk));
      });
    }

    testWidgets('a nudge shorter than the threshold does not move it', (
      tester,
    ) async {
      // Without the threshold the header flickers on every small scroll
      // correction, which is worse than a header that never hides at all.
      await tester.pumpWidget(host(screen()));
      await tester.pumpAndSettle();

      await tester.drag(find.text('Row 5'), const Offset(0, -20));
      await tester.pumpAndSettle();

      expect(tester.getRect(find.byType(PillHeader)).top, 0);
    });
  });

  group('search toggles the header in place', () {
    testWidgets('tapping search swaps the title row for a field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          screen(enableSearch: true, controller: controller, onChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('closing search clears the query, not just the field', (
      tester,
    ) async {
      // The field's `onChanged` does not fire for a programmatic `clear()`, so
      // clearing the controller alone leaves the list filtered by a query no
      // longer on screen. AnymeX calls only its `onSearchClear`, which most of
      // its own callers do not pass.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final seen = <String>[];

      await tester.pumpWidget(
        host(
          screen(
            enableSearch: true,
            controller: controller,
            onChanged: seen.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'naruto');
      await tester.pumpAndSettle();
      expect(seen.last, 'naruto');

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      expect(seen.last, isEmpty);
      expect(controller.text, isEmpty);
    });

    testWidgets('the clear button appears as the field is typed into', (
      tester,
    ) async {
      // It reads the controller through a listener rather than once at build
      // time: a button that only turns up on the next rebuild for some other
      // reason is worse than none.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          screen(enableSearch: true, controller: controller, onChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Clear'), findsNothing);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.byTooltip('Clear'), findsOneWidget);
    });
  });

  group('the segmented control cannot overflow', () {
    // Material's `TabBar` overflowed at 320, 360 and 384 on this very screen
    // and `flutter analyze` was clean throughout. Every segment here is
    // `1 / total` of the track by construction, so there is no intrinsic-width
    // negotiation left to lose.
    for (final width in <double>[280, 320, 360, 384]) {
      testWidgets('three long labels at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          host(
            Scaffold(
              body: SegmentedTabs(
                tabs: const [
                  Text('Installed'),
                  Text('Available'),
                  Text('Updates'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Every label inside its own third, with the track's 4px inset
        // allowed for. The selected segment is *painted* at 1.03 to lift it,
        // so its label is measured against a third scaled by the same amount:
        // that is a transform, not extra room, and asserting the flat third
        // against it fails on the animation rather than on a bug.
        final track = tester.getRect(find.byType(SegmentedTabs));
        final third = (track.width - Chrome.gutter * 2 - 8) / 3;
        for (final (i, label) in [
          'Installed',
          'Available',
          'Updates',
        ].indexed) {
          final rect = tester.getRect(find.text(label));
          final room = i == 0 ? third * _selectedScale : third;
          expect(
            rect.width,
            lessThanOrEqualTo(room + 0.5),
            reason: '"$label" is wider than its segment at $width',
          );
          expect(
            rect.center.dx,
            closeTo(track.left + Chrome.gutter + 4 + third * (i + 0.5), 1),
          );
        }
      });
    }

    testWidgets('the selected pill sits over the selected segment', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SegmentedTabs(
              tabs: const [Text('A'), Text('B'), Text('C')],
              selectedIndex: 2,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = tester.getRect(find.byType(FractionallySizedBox));
      final third = tester.getRect(find.text('C'));
      expect(indicator.center.dx, closeTo(third.center.dx, 1));
    });

    testWidgets('tapping a segment reports its index, and the selected one '
        'reports nothing', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(
        host(
          Scaffold(
            body: SegmentedTabs(
              tabs: const [Text('A'), Text('B')],
              selectedIndex: 0,
              onSelected: taps.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('B'));
      expect(taps, [1]);

      await tester.tap(find.text('A'));
      expect(taps, [1], reason: 're-selecting the current tab is not a change');
    });
  });

  group('the row shapes', () {
    testWidgets('a tile with an icon carries the tinted leading square', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Scaffold(
            body: ChromeTile(
              title: 'Downloads',
              subtitle: 'Nothing queued',
              icon: Icons.download_rounded,
              // A chevron only where there is somewhere to go.
              onTap: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.download_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      final square = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.download_rounded),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(square.width, Chrome.leadingSize);
      expect(square.height, Chrome.leadingSize);
    });

    testWidgets('a tappable tile gets a chevron', (tester) async {
      await tester.pumpWidget(
        host(
          Scaffold(
            body: ChromeTile(
              title: 'Downloads',
              icon: Icons.download_rounded,
              onTap: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('a long title ellipsises rather than pushing its badge off', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        host(
          const Scaffold(
            body: ChromeTile(
              title: 'A source with a really rather long published name',
              icon: Icons.extension_rounded,
              titleSuffix: Text('18+'),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('18+'), findsOneWidget);
      expect(tester.getRect(find.text('18+')).right, lessThanOrEqualTo(320));
    });

    testWidgets('a card passes its tap through', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Scaffold(
            body: ChromeCard(
              onTap: () => taps++,
              child: const SizedBox(height: 60, width: 200),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ChromeCard));
      expect(taps, 1);
    });
  });

  testWidgets('a widget with no header above it asks for no gap', (
    tester,
  ) async {
    // `ChromeHeaderScope.of` answering 0 rather than throwing is what lets a
    // converted row be dropped onto a plain `Scaffold` — a sheet, a dialog —
    // without carrying the scaffold with it.
    late double height;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: Builder(
            builder: (context) {
              height = ChromeHeaderScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(height, 0);
  });
}
