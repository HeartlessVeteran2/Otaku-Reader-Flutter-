import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/navigation/app_shell.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/features/home/controllers/home_controller.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

import 'helpers/network_status_fake.dart';
import 'helpers/category_fakes.dart';

import 'helpers/fake_source_repository.dart';
import 'helpers/isar_test_env.dart';

/// The home screen's shelves are AniList-driven, and these suites are about the
/// shell's chrome. Every lookup answers "nothing", which is also the path a
/// first launch with no network takes.
class _NoAniList implements AniListRepository {
  @override
  Future<AniListMedia?> media(int id) async => null;
  @override
  Future<TitleMatch?> match(String title) async => null;
  @override
  Future<List<TitleMatch>> searchCandidates(String title) async => const [];
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async =>
      const {};
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  // The full production schema list, because the shell now builds the real
  // Library tab and that reads manga rows, not just the key/value tier.
  setUpAll(
    () async =>
        env = await IsarTestEnv.open('shell', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  setUp(() {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
    // One instance, registered and injected — see one_ui_test.dart.
    final nsfw = NsfwPreference();
    Get.put<NsfwPreference>(nsfw);
    // The Library tab is a real screen now, so the shell cannot be built
    // without its controller.
    Get.put<LibraryController>(
      LibraryController(
        library: LibraryRepositoryImpl(),
        sources: const NoSources(),
        categories: const EmptyCategories(),
      ),
    );
    // So is the Home tab, which is the shell's default landing tab.
    Get.put<HomeController>(
      HomeController(
        anilist: _NoAniList(),
        library: LibraryRepositoryImpl(),
        nsfw: nsfw,
      ),
    );
  });

  Widget wrap(Widget child, {Size size = const Size(400, 800)}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(home: child),
  );

  testWidgets('renders a bottom bar on a narrow viewport', (tester) async {
    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('renders a rail at or above the 600px breakpoint', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const AppShell(), size: const Size(900, 800)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('selecting a tab persists it for the next launch', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    // Library is index 1; tapping it must both switch the view and write the
    // choice, so a relaunch reopens where the user left off.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(General.lastOpenedTab.get<int>(0), 1);
    expect(
      find.textContaining('Your library is empty'),
      findsOneWidget,
      reason: 'the Library tab is showing, not just selected',
    );
  });

  testWidgets('the Updates tab carries an unread badge', (tester) async {
    // The badge is the only thing that tells a user a refresh found anything
    // while they were on another tab.
    final library = LibraryRepositoryImpl();
    await library.upsertFromSource(
      sourceId: 7,
      url: '/m',
      manga: MManga(
        name: 'Example',
        chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
      ),
    );
    await library.toggleFavorite(7, '/m');
    // A second fetch, so the new chapter counts as an update rather than as
    // part of a first import.
    await library.upsertFromSource(
      sourceId: 7,
      url: '/m',
      manga: MManga(
        name: 'Example',
        chapters: [
          MChapter(url: '/c-1', name: 'Chapter 1'),
          MChapter(url: '/c-2', name: 'Chapter 2'),
        ],
      ),
    );

    final updates = UpdatesController(
      library: library,
      sources: const NoSources(),
      network: FakeNetworkStatus(),
    )..onInit();
    Get.put<UpdatesController>(updates);
    await tester.pumpAndSettle();

    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Badge, '1'), findsOneWidget);

    await updates.markRead(updates.updates.single, true);
    await tester.pumpAndSettle();

    expect(
      find.byType(Badge),
      findsNothing,
      reason: 'a read update is still listed, but it is not outstanding',
    );

    // The write notifies every library watcher, and each debounces its reload.
    // Leaving that timer pending fails the widget test's own invariant check —
    // which is the framework catching exactly the leak the real onClose exists
    // to prevent.
    updates.onClose();
  });

  testWidgets('a persisted tab index out of range is clamped, not crashed', (
    tester,
  ) async {
    // A build that removes a tab must not brick the app for anyone whose stored
    // index pointed at it.
    General.lastOpenedTab.set<int>(99);

    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
