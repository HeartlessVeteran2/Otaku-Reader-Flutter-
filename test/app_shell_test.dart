import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/navigation/app_shell.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';

import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

/// The library screen only needs a base URL per source for cover headers; these
/// suites do not exercise that, so every lookup answers "no source".
class _NoSources implements SourceRepository {
  @override
  Future<Source?> sourceById(int id) async => null;
  @override
  Future<SourceMethods> methodsFor(int id) async => throw UnimplementedError();
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
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
    // The Library tab is a real screen now, so the shell cannot be built
    // without its controller.
    Get.put<LibraryController>(
      LibraryController(
        library: LibraryRepositoryImpl(),
        sources: _NoSources(),
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
