import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/browse/screens/extensions_screen.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

Source _source({
  required int id,
  String name = 'Example',
  String? code,
  String version = '1.0.0',
  String versionLast = '1.0.0',
}) => Source()
  ..sourceId = id
  ..name = name
  ..lang = 'en'
  ..sourceCode = code
  ..version = version
  ..versionLast = versionLast;

class _StubExtensions implements ExtensionRepository {
  _StubExtensions(this.rows);
  List<Source> rows;
  int installs = 0;

  @override
  Future<List<Source>> listAll() async => rows;
  @override
  Future<Source> install(Source s) async {
    installs++;
    return s..sourceCode = 'CODE';
  }

  @override
  Future<Source> update(Source s) async => s;
  @override
  Future<Source> uninstall(Source s) async => s..sourceCode = null;
  @override
  Future<List<RefreshResult>> refreshAll() async => const [];
  @override
  Future<RefreshResult> refresh(String url) async =>
      RefreshResult(repoUrl: url);
  @override
  Future<RefreshResult> addRepo(ExtensionRepo r) async =>
      RefreshResult(repoUrl: r.url);
  @override
  Future<void> removeRepo(String url) async {}
  @override
  Future<List<ExtensionRepo>> getRepos() async => const [];
}

class _StubSources implements SourceRepository {
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
  @override
  Future<SourceMethods> methodsFor(int id) async => throw UnimplementedError();
  @override
  Future<Source?> sourceById(int id) async => null;
  @override
  Future<void> markUsed(int id) async {}
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('extui', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() {
    env!.clear();
    Get.reset();
  });

  Future<_StubExtensions> pump(WidgetTester tester, List<Source> rows) async {
    final extensions = _StubExtensions(rows);
    Get.put<ExtensionsController>(
      ExtensionsController(
        extensions: extensions,
        sources: _StubSources(),
        nsfw: NsfwPreference(),
      ),
    );
    await tester.pumpWidget(const GetMaterialApp(home: ExtensionsScreen()));
    await tester.pumpAndSettle();
    return extensions;
  }

  testWidgets('renders the three tabs without an Obx misuse error', (
    tester,
  ) async {
    // Obx throws "improper use of a GetX has been detected" when a builder
    // reads no observable. That only shows at runtime, so the cheapest guard is
    // to actually build the screen.
    await pump(tester, [_source(id: 1, name: 'Installed', code: 'X')]);

    expect(find.text('Extensions'), findsOneWidget);
    expect(find.text('Installed'), findsWidgets);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Updates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an installed source shows on the Installed tab', (tester) async {
    await pump(tester, [
      _source(id: 1, name: 'MangaRead', code: 'X'),
      _source(id: 2, name: 'Not installed'),
    ]);

    expect(find.text('MangaRead'), findsOneWidget);
    expect(find.text('Not installed'), findsNothing);
  });

  testWidgets('tapping Install calls through to the repository', (
    tester,
  ) async {
    final extensions = await pump(tester, [_source(id: 2, name: 'Available')]);

    await tester.tap(find.text('Available').last);
    await tester.pumpAndSettle();
    expect(find.text('Install'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pumpAndSettle();

    expect(extensions.installs, 1);
  });

  testWidgets('the updates tab carries a count badge', (tester) async {
    await pump(tester, [
      _source(id: 1, name: 'Stale', code: 'X', versionLast: '2.0.0'),
    ]);

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'an empty catalogue explains itself rather than showing nothing',
    (tester) async {
      await pump(tester, []);

      expect(find.textContaining('No extensions installed'), findsOneWidget);
    },
  );
}
