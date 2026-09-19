import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
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

  /// Every URL `addRepo` was asked for, in order.
  final adds = <String>[];

  /// URLs this stub refuses, so a paste can be part success and part failure.
  Set<String> failingAdds = const {};

  @override
  Future<RefreshResult> addRepo(ExtensionRepo r) async {
    adds.add(r.url);
    if (failingAdds.contains(r.url)) {
      return RefreshResult(repoUrl: r.url, error: 'nope');
    }
    // Replaces rather than appends, which is the contract `addRepo` documents:
    // "adding an already-present URL refreshes it rather than duplicating it".
    // A fake that appends would let a duplicate in a pasted list look like two
    // repositories and nothing would notice. Flagged by `codeant-ai`.
    repos = [...repos.where((e) => e.url != r.url), r];
    return RefreshResult(repoUrl: r.url);
  }

  final removals = <String>[];

  /// Holds a removal open, so the row's in-flight state can be observed.
  Future<void>? gateRemove;

  /// Thrown by the next removal, for the path where the database gives out.
  Object? removeThrows;

  @override
  Future<void> removeRepo(String url) async {
    removals.add(url);
    final gate = gateRemove;
    if (gate != null) await gate;
    final boom = removeThrows;
    if (boom != null) throw boom;
    repos = repos.where((r) => r.url != url).toList();
    rows = rows.where((s) => s.repoUrl != url || s.isInstalled).toList();
  }

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

  group('the rows clear the floating header', () {
    // This screen supplies its own body -- three tabs, each its own
    // scrollable -- so `ChromeScaffold` cannot insert the gap for it and each
    // list pads itself from `ChromeHeaderScope`. Forgetting that renders the
    // first row *behind* a translucent, blurred pill, which reads as a design
    // flourish rather than as a row nobody can press.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await pump(tester, [
          for (var i = 1; i <= 8; i++)
            _source(id: i, name: 'Source $i', code: 'X'),
        ]);

        final header = tester.getRect(find.byType(PillHeader));
        final row = tester.getRect(find.text('Source 1'));
        expect(row.top, greaterThanOrEqualTo(header.bottom));
      });
    }

    testWidgets('and so does the empty state', (tester) async {
      await pump(tester, []);

      final header = tester.getRect(find.byType(PillHeader));
      final message = tester.getRect(
        find.textContaining('No extensions installed'),
      );
      expect(message.top, greaterThanOrEqualTo(header.bottom));
    });
  });

  testWidgets('searching filters the list from inside the header pill', (
    tester,
  ) async {
    // The permanent field under the app bar is gone: it cost 52px of every
    // screenful for a control used occasionally. What replaces it has to
    // actually filter, which is the half that is easy to lose in the move.
    await pump(tester, [
      _source(id: 1, name: 'MangaRead', code: 'X'),
      _source(id: 2, name: 'Zinmanga', code: 'X'),
    ]);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zin');
    await tester.pumpAndSettle();

    expect(find.text('Zinmanga'), findsOneWidget);
    expect(find.text('MangaRead'), findsNothing);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    expect(find.text('MangaRead'), findsOneWidget);
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

  group('the repositories screen says how each one is behaving', () {
    const url = 'https://example.test/index.json';

    /// Opens the Repositories screen over a catalogue and a health map.
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

      // Frames, not `pumpAndSettle`. The screen spins while its first read is
      // held open, and `pumpAndSettle` waits for every animation to stop — so
      // it cannot return until the gate opens, which is the one thing this
      // test needs to control.
      Future<void> advance() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      // Opening the screen starts reload #1, which hangs on that gate.
      await tester.tap(find.byTooltip('Repositories'));
      await advance();
      expect(find.text('Stale repo'), findsNothing);

      // Reload #2, started later and ungated, sees the renamed repository.
      // Adding is a dialog behind the FAB now rather than a field in a sheet,
      // so the confirm is found by its button type: 'Add' labels both.
      extensions.repos = const [ExtensionRepo(url: url, name: 'Fresh repo')];
      await tester.tap(find.byType(FloatingActionButton));
      await advance();
      await tester.enterText(
        find.byType(TextField).last,
        'https://added.test/index.json',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await advance();
      expect(find.text('Fresh repo'), findsOneWidget);

      // Now let the stale one land. It must be dropped, not painted.
      held.complete();
      await advance();

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

  group('the repositories screen, as a screen', () {
    const alpha = 'https://alpha.test/repos/index.json';
    const beta = 'https://beta.test/index.json';

    Future<_StubExtensions> open(
      WidgetTester tester, {
      List<Source> rows = const [],
      List<ExtensionRepo> repos = const [
        ExtensionRepo(url: alpha, name: 'Alpha'),
      ],
      Size? surface,
    }) async {
      if (surface != null) {
        await tester.binding.setSurfaceSize(surface);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      }
      final extensions = await pump(tester, rows, repos: repos);
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();
      return extensions;
    }

    testWidgets('splits the URL into a path over its host', (tester) async {
      // A single ellipsised URL hides exactly the end that tells two indexes
      // on one host apart. AnymeX splits it; this takes that.
      await open(tester);

      expect(find.text('/repos/index.json'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text(alpha), findsNothing);
    });

    testWidgets('copies the URL', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await open(tester);
      await tester.tap(find.byTooltip('Copy URL'));
      await tester.pumpAndSettle();

      // The whole URL, not the path the row shows: what is on screen is split
      // for reading, and what is copied has to be pasteable.
      expect(copied, [alpha]);
    });

    group('removing asks only when it has something to say', () {
      testWidgets('nothing installed removes straight away', (tester) async {
        // Confirming "its extensions will no longer be listed" is confirming
        // exactly what was just asked for, and it trains people to dismiss
        // the dialog that does matter.
        final extensions = await open(
          tester,
          rows: [_source(id: 1, name: 'Not installed', repoUrl: alpha)],
        );

        await tester.tap(find.byTooltip('Remove this repository'));
        await tester.pumpAndSettle();

        expect(find.text('Remove this repository?'), findsNothing);
        expect(extensions.removals, [alpha]);
      });

      testWidgets('an installed extension is warned about first', (
        tester,
      ) async {
        final extensions = await open(
          tester,
          rows: [_source(id: 1, name: 'Installed', code: 'X', repoUrl: alpha)],
        );

        await tester.tap(find.byTooltip('Remove this repository'));
        await tester.pumpAndSettle();

        // Named, because "stays and keeps working but stops updating" is the
        // surprise, and it is not reversible by re-adding the repository.
        expect(find.textContaining('stops receiving updates'), findsOneWidget);
        expect(extensions.removals, isEmpty);

        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(extensions.removals, [alpha]);
      });

      testWidgets('cancelling that warning removes nothing', (tester) async {
        final extensions = await open(
          tester,
          rows: [_source(id: 1, name: 'Installed', code: 'X', repoUrl: alpha)],
        );

        await tester.tap(find.byTooltip('Remove this repository'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(extensions.removals, isEmpty);
      });
    });

    testWidgets('a row being removed dims, spins and stops filtering', (
      tester,
    ) async {
      // AnymeX's per-row state, and it replaces a blocking dialog rather than
      // the warning above: the list stays readable while one row works.
      final held = Completer<void>();
      final extensions = await open(
        tester,
        rows: [_source(id: 1, name: 'Not installed', repoUrl: alpha)],
      );
      extensions.gateRemove = held.future;

      await tester.tap(find.byTooltip('Remove this repository'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 0.4);
      // The delete button is gone while its own removal is in flight, so the
      // second tap has no target rather than a second removal.
      expect(find.byTooltip('Remove this repository'), findsNothing);

      held.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    group('adding takes several URLs at once', () {
      testWidgets('split on newlines and commas', (tester) async {
        final extensions = await open(tester, repos: const []);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          ' https://one.test/index.json\n'
          'https://two.test/index.json , https://three.test/index.json ',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        expect(extensions.adds, [
          'https://one.test/index.json',
          'https://two.test/index.json',
          'https://three.test/index.json',
        ]);
        // Closed, because nothing failed.
        expect(find.byType(TextField), findsNothing);
      });

      testWidgets('a bad one in the paste does not discard the good ones', (
        tester,
      ) async {
        final extensions = await open(tester, repos: const []);
        extensions.failingAdds = {'https://bad.test/index.json'};

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).last,
          'https://good.test/index.json\nhttps://bad.test/index.json',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();

        // Held open, saying what landed and what did not, with only the
        // failures left to retry. Closing would report the successes and
        // silently drop the rest.
        expect(find.textContaining('1 repository added'), findsOneWidget);
        expect(find.textContaining('https://bad.test'), findsWidgets);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).last)
              .controller!
              .text,
          'https://bad.test/index.json',
        );
      });
    });

    testWidgets('a removal that fails says so', (tester) async {
      // The row un-dims either way, so without this the user sees a spinner
      // stop, the repository still there, and nothing said — which reads as
      // the app being broken rather than as the removal having failed. The
      // same rule `open_link.dart` exists for.
      final extensions = await open(
        tester,
        rows: [_source(id: 1, name: 'Not installed', repoUrl: alpha)],
      );
      extensions.removeThrows = StateError('disk gave out');

      await tester.tap(find.byTooltip('Remove this repository'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Could not remove'), findsOneWidget);
      // Still listed, because it still exists.
      expect(find.text('/repos/index.json'), findsOneWidget);
      // And still removable: the row is back to its ordinary state.
      expect(find.byTooltip('Remove this repository'), findsOneWidget);
    });

    testWidgets('the same URL twice in a paste is one repository', (
      tester,
    ) async {
      await open(tester, repos: const []);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'https://one.test/index.json\nhttps://one.test/index.json',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // Both are offered, because refusing the second would mean this screen
      // deciding what the repository layer already decides — and it refreshes
      // rather than duplicating.
      expect(find.text('/index.json'), findsOneWidget);
    });

    testWidgets('a check dated in the future does not claim to be recent', (
      tester,
    ) async {
      // `checkedAt` is persisted, so a clock correction can leave a record
      // ahead of `now`. The difference is then negative, and a bare
      // "under a minute" test renders it as "just now" — a claim about when
      // the check happened, made from a number that cannot say.
      final extensions = await pump(
        tester,
        const [],
        repos: const [ExtensionRepo(url: alpha, name: 'Alpha')],
      );
      extensions.health = {
        alpha: RepoHealth(
          checkedAt: DateTime.now().add(const Duration(days: 1)),
        ),
      };
      await tester.tap(find.byTooltip('Repositories'));
      await tester.pumpAndSettle();

      expect(find.textContaining('just now'), findsNothing);
      expect(find.textContaining('checked'), findsOneWidget);
    });

    for (final width in <double>[320, 360, 384]) {
      testWidgets('a repository row lays out at ${width.toInt()}px', (
        tester,
      ) async {
        await open(
          tester,
          surface: Size(width, 720),
          rows: [
            _source(id: 1, name: 'Installed', code: 'X', repoUrl: alpha),
            _source(id: 2, name: 'Other', code: 'X', repoUrl: beta),
          ],
          repos: const [
            ExtensionRepo(url: alpha, name: 'Alpha'),
            ExtensionRepo(url: beta),
          ],
        );

        expect(tester.takeException(), isNull);
        // Below the floating pills, not behind them.
        final header = tester.getRect(find.byType(PillHeader));
        final first = tester.getRect(find.text('/repos/index.json'));
        expect(first.top, greaterThanOrEqualTo(header.bottom));
      });
    }
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
      // The name, which is unambiguous again: the repositories are a pushed
      // route now, so the extension rows carrying the same provenance label
      // are offstage behind it. The card splits the URL into a monospace path
      // over that label, and two repositories on different hosts share the
      // path `/index.json`.
      await tester.tap(find.text('Alpha'));
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
      await tester.tap(find.text('Alpha'));
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
      await tester.tap(find.text('Alpha'));
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
        await tester.tap(find.text('Alpha'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Show every repository'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
