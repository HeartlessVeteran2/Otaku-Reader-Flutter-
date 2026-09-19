import 'dart:async';

import 'package:flutter/material.dart';
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
  String? repoUrl,
}) => Source()
  ..sourceId = id
  ..name = name
  ..lang = 'en'
  ..sourceCode = code
  ..version = version
  ..versionLast = versionLast
  ..repoUrl = repoUrl;

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
  Future<List<ExtensionRepo>> getRepos() async {
    // Snapshotted **before** the gate, not after. Returning the field's
    // current value would hand the resumed stale call the *newer* data, so
    // both reloads would produce the same thing and the test could not tell a
    // dropped stale answer from a published one.
    final snapshot = repos;
    // One-shot, so the *first* reload can be held open while a later one
    // overtakes it. A permanent gate would hold both and prove nothing.
    final gate = gateFirstRepoRead;
    if (gate != null) {
      gateFirstRepoRead = null;
      await gate;
    }
    return snapshot;
  }

  List<ExtensionRepo> repos = const [];
  Future<void>? gateFirstRepoRead;
  @override
  Future<Map<String, RepoHealth>> repoHealth() async => health;
  Map<String, RepoHealth> health = const {};
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

  Future<_StubExtensions> pump(
    WidgetTester tester,
    List<Source> rows, {
    List<ExtensionRepo> repos = const [],
  }) async {
    // Seeded before the controller is built: `onInit` calls `load()`, which is
    // what fills `repoLabels`, so repos assigned afterwards would never reach
    // the rows.
    final extensions = _StubExtensions(rows)..repos = repos;
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

  group('the repo sheet says how each repository is behaving', () {
    const url = 'https://example.test/index.json';

    /// Opens the Repositories sheet over a catalogue and a health map.
    Future<void> openSheet(
      WidgetTester tester, {
      required List<Source> rows,
      required Map<String, RepoHealth> health,
      List<ExtensionRepo> repos = const [
        ExtensionRepo(url: url, name: 'Example repo'),
      ],
      Size? surface,
    }) async {
      if (surface != null) {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      final extensions = await pump(tester, rows);
      extensions
        ..repos = repos
        ..health = health;
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
    }

    // Three states, never two. A repo nobody has refreshed must not borrow
    // either of the others: "never checked" is something the user can act on,
    // and calling it a failure is a claim about a request never made.
    testWidgets('a repository nobody has refreshed says so', (tester) async {
      await openSheet(
        tester,
        rows: [_source(id: 1, name: 'A', repoUrl: url)],
        health: const {},
      );

      expect(find.textContaining('never checked'), findsOneWidget);
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets('a healthy repository says what it carries', (tester) async {
      await openSheet(
        tester,
        rows: [
          _source(id: 1, name: 'A', repoUrl: url),
          _source(id: 2, name: 'B', repoUrl: url),
          // A source from elsewhere must not be counted against this repo.
          _source(id: 3, name: 'C', repoUrl: 'https://other.test/index.json'),
        ],
        health: {url: RepoHealth(checkedAt: DateTime.now())},
      );

      expect(find.textContaining('2 extensions'), findsOneWidget);
      expect(find.textContaining('checked just now'), findsOneWidget);
    });

    testWidgets('a failing repository is marked, in the error colour', (
      tester,
    ) async {
      await openSheet(
        tester,
        rows: [_source(id: 1, name: 'A', repoUrl: url)],
        health: {
          url: RepoHealth(
            checkedAt: DateTime.now().subtract(const Duration(hours: 3)),
            error: 'SocketException: host unreachable',
          ),
        },
      );

      final line = find.textContaining('failed 3h ago');
      expect(line, findsOneWidget);
      // The colour is the point, not decoration: it is what makes one bad repo
      // findable among healthy ones without reading every line. A test that
      // asserted only the text would pass with the colour dropped.
      final context = tester.element(line);
      expect(
        tester.widget<Text>(line).style?.color,
        Theme.of(context).colorScheme.error,
      );
    });

    // The sheet must publish the newest answer, not the last one to arrive.
    //
    // Driven entirely through the UI: the `initState` reload is held open, a
    // second reload is triggered by adding a repository and completes first,
    // and only then is the stale one released. Forced with a gated stub,
    // because today's repository chain is synchronous underneath and so cannot
    // actually interleave — the guard is for when that stops being true.
    testWidgets('a slow earlier reload does not publish over a newer', (
      tester,
    ) async {
      final held = Completer<void>();
      final extensions = await pump(tester, [
        _source(id: 1, name: 'A', repoUrl: url),
      ]);
      extensions
        ..repos = const [ExtensionRepo(url: url, name: 'Stale repo')]
        ..health = const {}
        ..gateFirstRepoRead = held.future;

      // Opening the sheet starts reload #1, which hangs on that gate.
      // `pumpAndSettle` finishes the sheet's entrance animation without
      // completing the gate — it waits on frames, not futures — and the button
      // is not hit-testable until that animation is done.
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      expect(find.text('Stale repo'), findsNothing);

      // Reload #2, started later and ungated, sees the renamed repository.
      extensions.repos = const [ExtensionRepo(url: url, name: 'Fresh repo')];
      await tester.enterText(
        find.byType(TextField).last,
        'https://added.test/index.json',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Fresh repo'), findsOneWidget);

      // Now let the stale one land. It must be dropped, not painted.
      held.complete();
      await tester.pumpAndSettle();

      expect(find.text('Fresh repo'), findsOneWidget);
      expect(find.text('Stale repo'), findsNothing);
    });

    // A fixed-width row on a narrow phone is the eighth instance in CLAUDE.md
    // of `flutter analyze` being blind to layout, and the default 800px test
    // viewport hides it. 320 is the narrow phone. Parameterised so a failure
    // names the state that overflowed rather than just "the sheet" — including
    // an **empty** repo list, which renders none of these rows and so says
    // whether an overflow belongs to the row or to the sheet around it.
    for (final state
        in <
          ({
            String name,
            List<ExtensionRepo> repos,
            Map<String, RepoHealth> health,
          })
        >[
          (name: 'no repositories at all', repos: const [], health: const {}),
          (
            name: 'never checked',
            repos: const [ExtensionRepo(url: url, name: 'Example repo')],
            health: const {},
          ),
          (
            name: 'healthy',
            repos: const [ExtensionRepo(url: url, name: 'Example repo')],
            health: {url: RepoHealth(checkedAt: DateTime.now())},
          ),
          (
            name: 'failing, with a long message',
            repos: const [ExtensionRepo(url: url, name: 'Example repo')],
            health: {
              url: RepoHealth(
                checkedAt: DateTime.now(),
                error: 'SocketException: no route to host after 30s',
              ),
            },
          ),
        ]) {
      testWidgets('${state.name} lays out at 320px', (tester) async {
        await openSheet(
          tester,
          rows: [_source(id: 1, name: 'A', repoUrl: url)],
          repos: state.repos,
          health: state.health,
          surface: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // The tab bar overflowed on real phones, not just tiny ones: measured at
  // 24px over at 320, 11px at 360 and 2.7px at 384, clean only from 411 up. So
  // these widths are the guard, and 360/384 are the ones that matter — a test
  // at 320 alone would have looked like a narrow-phone nicety.
  for (final width in <double>[320, 360, 384, 411]) {
    testWidgets('the tab bar lays out at ${width.toInt()}px', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // With an update badge, which is the widest the third tab ever gets.
      await pump(tester, [
        _source(id: 1, name: 'A', code: 'X', versionLast: '2.0.0'),
      ]);

      expect(find.text('Installed'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  group('an extension row says where it came from', () {
    const alpha = 'https://alpha.test/index.json';

    testWidgets('a row names its repository', (tester) async {
      await pump(
        tester,
        [_source(id: 1, name: 'From alpha', code: 'X', repoUrl: alpha)],
        repos: const [ExtensionRepo(url: alpha, name: 'Alpha')],
      );

      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('a repository with no name falls back to its host', (
      tester,
    ) async {
      await pump(
        tester,
        [_source(id: 1, name: 'From alpha', code: 'X', repoUrl: alpha)],
        repos: const [ExtensionRepo(url: alpha)],
      );

      expect(find.text('alpha.test'), findsOneWidget);
    });

    // The row that matters. A detached source still works and will never
    // update again, and nothing else on the screen distinguishes it from a
    // current one — so the row has to say so, in the error colour.
    testWidgets('a detached row says it will not update', (tester) async {
      await pump(tester, [_source(id: 1, name: 'Orphan', code: 'X')]);

      final line = find.text('No repository — will not update');
      expect(line, findsOneWidget);
      final context = tester.element(line);
      expect(
        tester.widget<Text>(line).style?.color,
        Theme.of(context).colorScheme.error,
      );
    });

    // An unknown url is not the same as no url: only the second means frozen.
    testWidgets('a url no repository claims still shows a host, not nothing', (
      tester,
    ) async {
      await pump(tester, [
        _source(id: 1, name: 'Stray', code: 'X', repoUrl: alpha),
      ]);

      expect(find.text('alpha.test'), findsOneWidget);
      expect(find.text('No repository — will not update'), findsNothing);
    });
  });

  group('the repository filter', () {
    const alpha = 'https://alpha.test/index.json';
    const beta = 'https://beta.test/index.json';

    Future<_StubExtensions> pumpBoth(
      WidgetTester tester, {
      Size? surface,
    }) async {
      if (surface != null) {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      return pump(
        tester,
        [
          _source(id: 1, name: 'From alpha', code: 'X', repoUrl: alpha),
          _source(id: 2, name: 'From beta', code: 'X', repoUrl: beta),
          _source(id: 3, name: 'Orphan', code: 'X'),
        ],
        repos: const [
          ExtensionRepo(url: alpha, name: 'Alpha'),
          ExtensionRepo(url: beta, name: 'Beta'),
        ],
      );
    }

    testWidgets('no banner until a filter is on', (tester) async {
      await pumpBoth(tester);
      expect(find.byTooltip('Show every repository'), findsNothing);
    });

    testWidgets('tapping a repository filters and explains itself', (
      tester,
    ) async {
      await pumpBoth(tester);
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      // The URL, not the name: the name now appears on every row that
      // repository owns, so `find.text('Alpha')` matches the sheet row *and*
      // the provenance labels behind it.
      await tester.tap(find.text(alpha));
      await tester.pumpAndSettle();

      // The sheet closed, so without the banner the user would be left with a
      // shortened list and no reason given.
      expect(find.byTooltip('Show every repository'), findsOneWidget);
      expect(find.text('From alpha'), findsOneWidget);
      expect(find.text('From beta'), findsNothing);
      expect(find.text('Orphan'), findsNothing);
    });

    testWidgets('the detached group is offered, and finds them', (
      tester,
    ) async {
      await pumpBoth(tester);
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Extensions with no repository'));
      await tester.pumpAndSettle();

      expect(find.text('Orphan'), findsOneWidget);
      expect(find.text('From alpha'), findsNothing);
    });

    testWidgets('an offer that would find nothing is not made', (tester) async {
      await pump(
        tester,
        [_source(id: 1, name: 'From alpha', code: 'X', repoUrl: alpha)],
        repos: const [ExtensionRepo(url: alpha, name: 'Alpha')],
      );
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();

      expect(find.text('Extensions with no repository'), findsNothing);
    });

    testWidgets('clearing the filter brings everything back', (tester) async {
      await pumpBoth(tester);
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(alpha));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show every repository'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show every repository'), findsNothing);
      expect(find.text('From beta'), findsOneWidget);
      expect(find.text('Orphan'), findsOneWidget);
    });

    // A filtered-empty list must not claim the catalogue is empty. The empty
    // state was told only about the search query, so a repository filter that
    // matches nothing produced "No extensions installed yet" over a catalogue
    // that is in fact full.
    testWidgets('an empty result explains the filter, not the catalogue', (
      tester,
    ) async {
      await pumpBoth(tester);
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(alpha));
      await tester.pumpAndSettle();

      // Alpha has nothing on the Updates tab, so that tab is filtered-empty.
      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing matches'), findsOneWidget);
      expect(find.textContaining('No extensions installed yet'), findsNothing);
    });

    // Widths picked by measurement, not assumption: the tab bar's own overflow
    // lived at 360 and 384, not only at 320.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('rows and banner lay out at ${width.toInt()}px', (
        tester,
      ) async {
        await pumpBoth(tester, surface: Size(width, 640));
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Repositories'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(alpha));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Show every repository'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
