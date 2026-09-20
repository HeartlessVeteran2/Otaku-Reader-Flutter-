import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

import 'helpers/anilist_fakes.dart';
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

  /// Drags the list far enough to bring the reader and source rows up.
  Future<void> scrollDown(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
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

    await scrollDown(tester);

    for (final label in [
      'Reading layout',
      'Reading direction',
      'Keep the screen on',
      'Show the page number',
      'Show 18+ sources',
      'AniList',
    ]) {
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
      await scrollDown(tester);

      await tester.tap(find.text('Webtoon'));
      await tester.pumpAndSettle();

      // The key, not a controller: the reader reads this at open time and
      // there may be no reader alive to hold it.
      expect(ReaderKeys.readingLayout.get<int>(0), 1);
    });

    testWidgets('reading direction writes the key the reader reads', (
      tester,
    ) async {
      await open(tester);
      await scrollDown(tester);

      await tester.tap(find.text('Right to left'));
      await tester.pumpAndSettle();

      expect(ReaderKeys.readingDirection.get<int>(0), 1);
    });

    testWidgets('the selected segment follows the stored value', (
      tester,
    ) async {
      // The other direction: a selector that writes but never reads back
      // shows the wrong choice after a restart, and the write test above
      // cannot see that.
      ReaderKeys.readingDirection.set<int>(1);

      await open(tester);
      await scrollDown(tester);

      final tabs = tester.widget<SegmentedTabs>(
        find.ancestor(
          of: find.text('Right to left'),
          matching: find.byType(SegmentedTabs),
        ),
      );
      expect(tabs.selectedIndex, 1);
    });
  });

  testWidgets('a switch row writes the shared preference', (tester) async {
    // The switch must write the *shared* holder rather than the key directly
    // or a copy of its own, or the setting appears to do nothing until a
    // restart.
    nsfw.setShown(true);
    await open(tester);
    await scrollDown(tester);

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
    // silently. `didExceedMaxLines` is the question actually being asked.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: host(const SettingsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Every subtitle on screen is prose in a row whose height is free.
        var checked = 0;
        for (final element in find.byType(RichText).evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          // The segment labels and the row titles are capped on purpose --
          // those caps hold layout invariants (a segment is 1/n of the row;
          // a long title must not shove its trailing control off screen).
          if (paragraph.maxLines == 1) continue;
          checked++;
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: 'hidden text: "${paragraph.text.toPlainText()}"',
          );
        }
        // Without this the loop is hollow: a filter that matches nothing
        // passes every assertion it never makes.
        expect(
          checked,
          greaterThan(0),
          reason: 'no uncapped text was examined',
        );
      });
    }
  });
}
