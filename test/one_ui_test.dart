import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/repository/download_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/features/downloads/screens/downloads_screen.dart';
import 'package:otaku_reader/features/more/screens/about_screen.dart';
import 'package:otaku_reader/features/more/screens/more_screen.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

import 'helpers/fake_source_repository.dart';
import 'helpers/isar_test_env.dart';

/// These suites exist because a One UI conversion is exactly the kind of change
/// that analyses clean, passes every controller test, and then throws on the
/// device.
///
/// The specific hazard is the sliver slot. `OneUiScaffold` builds a
/// `CustomScrollView`, so everything handed to it must produce a `RenderSliver`
/// — and a plain box widget in that list is a *runtime* failure, invisible to
/// `flutter analyze` because `Widget` is the declared type either way. `Obx`
/// and `FutureBuilder` make it worse: they are composition widgets with no
/// render object of their own, so whether they are legal in a sliver slot
/// depends on what their builder happens to return.
///
/// Nothing else in the suite renders these screens, so without this file the
/// whole visual pass is unverified.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('oneui', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  late Directory root;

  setUp(() {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
    root = Directory.systemTemp.createTempSync('otaku-oneui');
    Get.put<DownloadRepository>(
      DownloadRepositoryImpl(
        sources: const NoSources(),
        library: LibraryRepositoryImpl(),
        root: root,
      ),
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) => MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: MaterialApp(home: child),
  );

  /// Every screen converted to [OneUiScaffold]. Rendering each one is the
  /// assertion: a box widget in a sliver slot throws during layout, so a clean
  /// pump *is* the proof that the sliver contract holds on that screen.
  final screens = <String, Widget Function()>{
    'Settings': () => const SettingsScreen(),
    'More': () => const MoreScreen(),
    'About': () => const AboutScreen(),
    'Downloads': () => const DownloadsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} renders inside a CustomScrollView', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CustomScrollView),
        findsOneWidget,
        reason: 'the collapsing header is what makes it One UI',
      );
      // The title is rendered twice while the header is expanded — once in the
      // bar and once in the large title — so this asserts presence, not count.
      expect(find.text(entry.key), findsWidgets);
    });

    testWidgets('${entry.key} still scrolls after its header collapses', (
      tester,
    ) async {
      // The collapse is the part most likely to break: a sliver that reports
      // the wrong extent lays out fine at rest and throws once it is scrolled.
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a group renders its label above the rows, not inside them', (
    tester,
  ) async {
    // The label sitting outside the rounded container is what separates a One
    // UI group from a Material section header, so it is worth pinning.
    await tester.pumpWidget(
      wrap(
        const OneUiScaffold(
          title: 'T',
          slivers: [
            SliverOneUiGroup(
              label: 'Group',
              children: [ListTile(title: Text('Row'))],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.getTopLeft(find.text('Group'));
    final row = tester.getTopLeft(find.text('Row'));
    expect(label.dy, lessThan(row.dy));
    expect(
      find.byType(ClipRRect),
      findsWidgets,
      reason: 'the rows are clipped to the group radius',
    );
  });

  testWidgets('an empty group renders nothing at all', (tester) async {
    // Not an empty rounded box: a group whose rows are all conditional is a
    // real case, and an empty container reads as a rendering bug.
    await tester.pumpWidget(
      wrap(
        const OneUiScaffold(
          title: 'T',
          slivers: [SliverOneUiGroup(label: 'Group', children: [])],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group'), findsNothing);
  });

  testWidgets('Settings keeps every control it had before the restyle', (
    tester,
  ) async {
    // The restyle must not lose a setting. A screen that reads better and does
    // less is a regression, so this names the controls rather than counting
    // them.
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    for (final label in [
      'Theme',
      'Pure black dark theme',
      'Colour source',
      'Tint from the cover',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    for (final label in [
      'Reading layout',
      'Reading direction',
      'Keep the screen on',
      'Show the page number',
      'Show 18+ sources',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Downloads shows its empty state through the sliver list', (
    tester,
  ) async {
    // The task list is an `Obx` in a sliver slot, which is legal only because
    // it returns a sliver on *both* branches. The empty branch is the one a
    // fresh install hits, and it is a different widget from the populated one.
    await tester.pumpWidget(wrap(const DownloadsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Nothing downloading'), findsOneWidget);
  });
}
