import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

import 'helpers/anilist_fakes.dart';
import 'helpers/hidden_text.dart';
import 'helpers/isar_test_env.dart';

/// Settings on the chrome vocabulary.
///
/// Two things here that `flutter analyze` cannot see, and both have shipped in
/// this project before:
///
/// - **A control that writes nothing.** The radio dialogs are gone, replaced
///   by in-row segmented selectors. A selector that renders the right label
///   and stores nothing is exactly the defect #50 just fixed twice over, and
///   it would look identical on screen.
/// - **A row that does not fit.** Every segment is `1 / options` of the row by
///   construction, so three options on a 320px phone at a doubled system font
///   is where a label stops being readable.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('settings', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  late NsfwPreference nsfw;

  setUp(() async {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
    // The same instance every other screen resolves. Registering one and
    // handing a different one to the screen is a harness that cannot fail
    // when a Settings write stops reaching Home.
    nsfw = NsfwPreference();
    Get.put<NsfwPreference>(nsfw);
    // Restored, because `AppBindings` always restores. An auth that never did
    // leaves every screen rendering the "still reading the keystore" branch.
    final auth = AniListAuth(storage: FakeVault(), clientId: '');
    await auth.restore();
    Get.put<AniListAuth>(auth);
  });

  tearDown(Get.reset);

  Widget host(Widget child) => MaterialApp(home: child);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pumpAndSettle();
  }

  /// Scrolls until [label] is on screen.
  ///
  /// Deliberately not a fixed drag. A fixed -600 broke the moment the Shape
  /// section was inserted above the reader rows, and the failure looked like
  /// "the control is gone" rather than "the list is longer" — the same shape
  /// as waiting on a turn count instead of on the condition.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps every control it had before the conversion', (
    tester,
  ) async {
    // A screen that reads better and does less is a regression, so this names
    // the controls rather than counting them.
    await open(tester);

    for (final label in [
      'Theme',
      'Pure black dark theme',
      'Colour source',
      'Tint from the cover',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    // Scrolled to one at a time rather than after a single jump to the top of
    // the section. The one-jump version asserted that everything below
    // "Reading layout" happened to fit on one screen, so adding a row pushed
    // the last label out of the viewport and failed a test about nothing
    // having been *removed*.
    for (final label in [
      'Reading layout',
      'Paged direction',
      'Continuous direction',
      'Keep the screen on',
      'Show the page number',
      'Show 18+ sources',
      'AniList',
    ]) {
      await scrollTo(tester, label);
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  group('the in-row selectors write the setting', () {
    // The radio dialog used to be the thing that wrote. Now the segment is,
    // and a segment that renders but stores nothing looks exactly like one
    // that works.

    testWidgets('theme mode', (tester) async {
      await open(tester);
      expect(Get.find<ThemeController>().themeMode.value, ThemeMode.system);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(Get.find<ThemeController>().themeMode.value, ThemeMode.dark);
    });

    testWidgets('colour source', (tester) async {
      await open(tester);
      final theme = Get.find<ThemeController>();
      final before = theme.source.value;

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();

      expect(theme.source.value, ThemeSource.custom);
      expect(theme.source.value, isNot(before));
    });

    testWidgets('reading layout writes the key the reader reads', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, 'Webtoon');

      await tester.tap(find.text('Webtoon'));
      await tester.pumpAndSettle();

      // The key, not a controller: the reader reads this at open time and
      // there may be no reader alive to hold it.
      expect(ReaderKeys.readingLayout.get<int>(0), 1);
    });

    /// The `SegmentedTabs` under a named row.
    ///
    /// Found through the row's *title*, not through a label. Both direction
    /// rows now render the same four labels, so `find.text('R → L')` matches
    /// twice and would tap whichever the tree happened to order first -- a test
    /// that passes while writing the wrong key.
    SegmentedTabs tabsUnder(WidgetTester tester, String title) =>
        tester.widget<SegmentedTabs>(
          find.descendant(
            of: find.ancestor(
              of: find.text(title),
              matching: find.byType(ChromeTile),
            ),
            matching: find.byType(SegmentedTabs),
          ),
        );

    Future<void> tapSegment(
      WidgetTester tester,
      String title,
      String label,
    ) async {
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text(title),
            matching: find.byType(ChromeTile),
          ),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('paged direction writes the key the reader reads', (
      tester,
    ) async {
      await open(tester);
      await scrollTo(tester, 'Paged direction');

      await tapSegment(tester, 'Paged direction', 'R → L');

      expect(
        ReaderKeys.readingDirection.get<int>(0),
        ReadingDirection.rightToLeft.index,
      );
    });

    testWidgets('continuous direction writes its own key, not the paged one', (
      tester,
    ) async {
      // The whole reason there are two rows. One shared value would mean a
      // reader coming off a right-to-left manga found their next webtoon
      // scrolling sideways -- so a write here must not reach the paged key,
      // and collapsing them has to fail this.
      await open(tester);
      await scrollTo(tester, 'Continuous direction');

      await tapSegment(tester, 'Continuous direction', 'B → T');

      expect(
        ReaderKeys.webtoonDirection.get<int>(0),
        ReadingDirection.bottomToTop.index,
      );
      expect(
        ReaderKeys.readingDirection.get<int?>(),
        isNull,
        reason: 'the paged direction was never touched',
      );
    });

    testWidgets('each row defaults to the direction its layout reads in', (
      tester,
    ) async {
      // With nothing stored, which is a fresh install. A shared default would
      // put both rows on the same segment, and vertical is wrong for paged
      // exactly as horizontal is wrong for a long strip.
      await open(tester);
      await scrollTo(tester, 'Continuous direction');

      expect(
        tabsUnder(tester, 'Paged direction').selectedIndex,
        ReadingDirection.leftToRight.index,
      );
      expect(
        tabsUnder(tester, 'Continuous direction').selectedIndex,
        ReadingDirection.topToBottom.index,
      );
    });

    testWidgets('the selected segment follows the stored value', (
      tester,
    ) async {
      // The other direction: a selector that writes but never reads back
      // shows the wrong choice after a restart, and the write test above
      // cannot see that.
      ReaderKeys.readingDirection.set<int>(ReadingDirection.bottomToTop.index);

      await open(tester);
      await scrollTo(tester, 'Paged direction');

      expect(
        tabsUnder(tester, 'Paged direction').selectedIndex,
        ReadingDirection.bottomToTop.index,
      );
    });
  });

  testWidgets('a switch row writes the shared preference', (tester) async {
    // The switch must write the *shared* holder rather than the key directly
    // or a copy of its own, or the setting appears to do nothing until a
    // restart.
    nsfw.setShown(true);
    await open(tester);
    await scrollTo(tester, 'Show 18+ sources');

    await tester.tap(find.text('Show 18+ sources'));
    await tester.pumpAndSettle();

    expect(
      nsfw.shown.value,
      isFalse,
      reason: 'the whole row is the tap target, as AnymeX makes it',
    );
  });

  testWidgets('the AniList row does not claim signed-out before it knows', (
    tester,
  ) async {
    // `isReady` is the state that is easy to miss: `AppBindings` launches
    // `restore()` unawaited, so there is a real interval where the token has
    // not been read and "Not signed in" is the opposite of the truth.
    await Get.delete<AniListAuth>();
    Get.put<AniListAuth>(
      AniListAuth(
        storage: FakeVault()..store['anilist_access_token'] = 'stored',
        clientId: 'abc',
        client: FakeClient(viewerBody()),
      ),
    );

    await tester.pumpWidget(host(const SettingsScreen()));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('AniList'), 200);

    expect(find.text('Checking…'), findsOneWidget);
    expect(
      find.text('Not signed in'),
      findsNothing,
      reason: 'the token has not been read, so that is not yet an answer',
    );
  });

  group('the rows start below the floating header', () {
    // ChromeHeaderScope answers 0 when nothing published one, which is right
    // for a row dropped into a sheet and silently wrong for a screen reading
    // it from the wrong side. What it produces is the first row rendered
    // behind a translucent pill: a flourish to look at, a control nobody can
    // press.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await open(tester);

        final header = tester.getRect(find.byType(PillHeader));
        final firstRow = tester.getRect(find.text('Appearance'));
        expect(
          firstRow.top,
          greaterThanOrEqualTo(header.bottom),
          reason: 'the first section label is under the pill, not behind it',
        );
      });
    }
  });

  group('a doubled system font hides nothing', () {
    // `takeException()` is blind to an ellipsis: the sentence is dropped
    // silently. What replaced the naive `didExceedMaxLines` loop, and why, is
    // in `helpers/hidden_text.dart` -- the short version is that the loop
    // could not fail, because since #48 there are no multi-line prose caps
    // left for it to catch.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        final screen = Size(width, 900);
        await tester.binding.setSurfaceSize(screen);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: host(const SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expectNoHiddenText(tester, screen: screen);
      });
    }
  });
}
