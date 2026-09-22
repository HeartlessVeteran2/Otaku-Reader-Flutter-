import 'dart:io';

import 'package:flutter/painting.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/anilist/anilist_progress_sync.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/screen_wakelock.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'package:otaku_reader/features/reader/screen_controls.dart';

import 'helpers/screen_controls_fake.dart';
import 'helpers/isar_test_env.dart';

/// Records what the reader asked the platform for.
///
/// The point of the seam: `WakelockPlus` is static, so without this a test can
/// assert only that the *key* round-trips -- which is exactly what was already
/// passing while the switch did nothing at all.
class _FakeWakelock implements ScreenWakelock {
  int enables = 0;
  int disables = 0;

  @override
  Future<void> enable() async => enables++;
  @override
  Future<void> disable() async => disables++;
}

const _sourceId = 9;
const _manga = '/manga/example';

class _Methods implements SourceMethods {
  _Methods(this.source);

  @override
  final Source source;

  /// Pages per chapter url, so a test can give each chapter a different length.
  Map<String, List<PageUrl>> pagesByChapter = {};
  Object? failWith;

  /// Every chapter the source was actually asked for. A downloaded chapter
  /// must not appear here — reading from disk that still hits the site is
  /// indistinguishable from not being downloaded at all.
  final pageListCalls = <String>[];

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    pageListCalls.add(url);
    if (failWith != null) throw failWith!;
    return pagesByChapter[url] ?? const [];
  }

  @override
  bool get supportsLatest => true;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MPages> getPopular(int p) async => MPages(list: []);
  @override
  Future<MPages> getLatestUpdates(int p) async => MPages(list: []);
  @override
  Future<MPages> search(String q, int p, FilterList f) async =>
      MPages(list: []);
  @override
  Future<MManga> getDetail(String url) async => MManga();
  @override
  FilterList getFilterList() => FilterList([]);
  @override
  List<SourcePreference> getSourcePreferences() => const [];
  @override
  void dispose() {}
}

class _Sources implements SourceRepository {
  _Sources(this.methods, this.row);
  final _Methods methods;
  final Source row;

  @override
  Future<SourceMethods> methodsFor(int id) async => methods;
  @override
  Future<Source?> sourceById(int id) async => row;
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

Source _row() => Source()
  ..sourceId = _sourceId
  ..name = 'Example Source'
  ..lang = 'en'
  ..sourceCode = 'X';

List<PageUrl> _pages(int n) => [
  for (var i = 0; i < n; i++) PageUrl('https://img/$i.jpg'),
];

/// Records what the reader asked to report, so the *transition* can be
/// asserted rather than just the end state.
class _SpyReporter implements AniListProgressReporter {
  final calls = <({int entryId, double? chapterNumber})>[];

  @override
  Future<AniListProgressOutcome> reportChapter({
    required int entryId,
    required double? chapterNumber,
  }) async {
    calls.add((entryId: entryId, chapterNumber: chapterNumber));
    return AniListProgressOutcome.written;
  }
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('reader', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<void> seed() => library.upsertFromSource(
    sourceId: _sourceId,
    url: _manga,
    manga: MManga(
      name: 'Example',
      chapters: [
        MChapter(url: '/c-1', name: 'Chapter 1'),
        MChapter(url: '/c-2', name: 'Chapter 2'),
        MChapter(url: '/c-3', name: 'Chapter 3'),
      ],
    ),
  );

  late _SpyReporter reporter;

  late _FakeWakelock wakelock;

  /// The screen controls the reader asked for — orientation, immersive and
  /// secure. Held so a test can assert the **request**, never the stored key:
  /// a round-trip test is exactly what passed the whole time two switches here
  /// shipped with nothing behind them.
  late FakeScreenControls screen;

  Future<(ReaderController, _Methods)> open(
    String chapterUrl, {
    Map<String, List<PageUrl>>? pages,
    bool secureSucceeds = true,
  }) async {
    final methods = _Methods(_row())
      ..pagesByChapter =
          pages ?? {'/c-1': _pages(3), '/c-2': _pages(4), '/c-3': _pages(2)};
    reporter = _SpyReporter();
    wakelock = _FakeWakelock();
    screen = FakeScreenControls(secureSucceeds: secureSucceeds);
    final c = ReaderController(
      sources: _Sources(methods, _row()),
      library: library,
      anilistProgress: reporter,
      wakelock: wakelock,
      screen: screen,
      sourceId: _sourceId,
      mangaUrl: _manga,
      chapterUrl: chapterUrl,
    )..onInit();
    // Waited on rather than pumped a fixed number of times: how many turns the
    // load takes depends on the path it goes down — reading a directory from
    // disk and clearing a stale pointer are both several more than a plain
    // fetch, and a fixed count silently returns an empty controller instead of
    // failing on what the test meant to assert.
    for (var i = 0; i < 100 && c.isLoading.value; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return (c, methods);
  }

  group('long-strip auto-detection', () {
    test('a manhwa opens in the continuous reader', () async {
      ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
      ReaderKeys.autoWebtoonMode.set<bool>(true);
      await library.upsertFromSource(
        sourceId: _sourceId,
        url: _manga,
        manga: MManga(
          name: 'Example',
          genre: ['Action', 'Manhwa'],
          chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
        ),
      );

      final (c, _) = await open('/c-1');

      expect(c.layout.value, ReadingLayout.webtoon);
      expect(c.layoutIsAuto.value, isTrue);
      c.onClose();
    });

    test('**it never writes the stored default**', () async {
      // The guard that carries this feature. Without it, opening one manhwa
      // rewrites the reader's default and every paged series afterwards opens
      // as a strip — a setting changed by a series rather than by a person.
      // AnymeX guards the same thing inside `_savePreferences`.
      ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
      ReaderKeys.autoWebtoonMode.set<bool>(true);
      await library.upsertFromSource(
        sourceId: _sourceId,
        url: _manga,
        manga: MManga(
          name: 'Example',
          genre: ['Webtoon'],
          chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
        ),
      );

      final (c, _) = await open('/c-1');
      expect(c.layout.value, ReadingLayout.webtoon, reason: 'in force');
      expect(
        ReaderKeys.readingLayout.get<int>(0),
        ReadingLayout.paged.index,
        reason: 'but the stored default is untouched',
      );
      c.onClose();
    });

    test(
      'choosing a layout by hand does persist, and clears the flag',
      () async {
        ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
        ReaderKeys.autoWebtoonMode.set<bool>(true);
        await library.upsertFromSource(
          sourceId: _sourceId,
          url: _manga,
          manga: MManga(
            name: 'Example',
            genre: ['Webtoon'],
            chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
          ),
        );

        final (c, _) = await open('/c-1');
        c.setLayout(ReadingLayout.paged);

        expect(c.layoutIsAuto.value, isFalse);
        expect(ReaderKeys.readingLayout.get<int>(0), ReadingLayout.paged.index);
        c.onClose();
      },
    );

    test('an ordinary manga is left alone', () async {
      ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
      ReaderKeys.autoWebtoonMode.set<bool>(true);
      await library.upsertFromSource(
        sourceId: _sourceId,
        url: _manga,
        manga: MManga(
          name: 'Example',
          genre: ['Action', 'Seinen'],
          chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
        ),
      );

      final (c, _) = await open('/c-1');

      expect(c.layout.value, ReadingLayout.paged);
      expect(c.layoutIsAuto.value, isFalse);
      c.onClose();
    });

    test('the switch turns it off', () async {
      ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
      ReaderKeys.autoWebtoonMode.set<bool>(false);
      await library.upsertFromSource(
        sourceId: _sourceId,
        url: _manga,
        manga: MManga(
          name: 'Example',
          genre: ['Webtoon'],
          chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
        ),
      );

      final (c, _) = await open('/c-1');

      expect(c.layout.value, ReadingLayout.paged);
      c.onClose();
    });

    test('a stored page width outside the slider range is clamped', () async {
      // A value above 1 would push a strip page past a viewport the continuous
      // body cannot pan; a 0 would erase the page outright.
      ReaderKeys.imageWidth.set<double>(2.5);
      await library.upsertFromSource(
        sourceId: _sourceId,
        url: _manga,
        manga: MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
        ),
      );

      final (c, _) = await open('/c-1');

      expect(c.pageLayout.value.widthFactor, 1.0);
      c.onClose();
    });
  });

  group('the screen settings a chapter holds', () {
    // Every assertion here reads the **request** the reader made, not the key
    // it stored. That is the whole reason `ReaderScreenControls` is a seam:
    // `SystemChrome` is static, so a host-VM test can neither call it nor
    // watch it, and the two Settings switches that shipped dead here both
    // round-tripped their key perfectly the entire time.

    test('applies the stored orientation on open', () async {
      ReaderKeys.orientationLock.set<int>(ReaderOrientation.landscape.index);

      final (c, _) = await open('/c-1');

      expect(screen.orientations.first, ReaderOrientation.landscape);
      expect(c.orientation.value, ReaderOrientation.landscape);
      c.onClose();
    });

    test('an out-of-range stored orientation is clamped, not thrown', () async {
      // The `int status = 5` row of the mistakes table: a build that removes a
      // member must not brick the reader for anyone whose stored index named
      // it. Clamped against `values.length`, never a literal.
      ReaderKeys.orientationLock.set<int>(99);

      final (c, _) = await open('/c-1');

      expect(c.orientation.value, ReaderOrientation.values.last);
      c.onClose();
    });

    test('releases orientation and immersive on close, whatever was set', () async {
      final (c, _) = await open('/c-1');
      screen.orientations.clear();
      screen.immersive.clear();

      c.onClose();
      await Future<void>.delayed(Duration.zero);

      // Unconditional on purpose. Keying the release on the setting strands
      // the whole app sideways when the switch is turned off mid-chapter: the
      // apply already happened and the restore would be skipped on the way out.
      expect(screen.orientations, [ReaderOrientation.system]);
      expect(screen.immersive, [false]);
    });

    test('the secure flag is not requested unless the setting is on', () async {
      final (c, _) = await open('/c-1');

      expect(screen.secure, isEmpty, reason: 'nothing asked for on open');
      c.onClose();
    });

    test('a refused secure flag is reported, not swallowed', () async {
      // The state that matters. A reader who turned this on and got a silent
      // no believes screenshots are blocked when they are not, so "requested
      // and refused" has to be distinguishable from "applied".
      ReaderKeys.secureScreen.set<bool>(true);

      final (c, _) = await open('/c-1', secureSucceeds: false);
      for (var i = 0; i < 10 && !c.secureRefused.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(screen.secure.first, isTrue, reason: 'it was asked for');
      expect(c.secureApplied.value, isFalse);
      expect(c.secureRefused.value, isTrue);
      c.onClose();
    });

    test('a refusal is remembered for the Settings switch to read', () async {
      // The reader is the only place the flag is ever requested, so without
      // this the refusal is discoverable only by opening a chapter — and the
      // switch a user actually toggles goes on implying screenshots are
      // blocked. `codeant-ai` filed it against the switch; this is the half
      // that lets the switch answer.
      ReaderKeys.secureScreen.set<bool>(true);

      final (c, _) = await open('/c-1', secureSucceeds: false);
      for (var i = 0; i < 10 && !c.secureRefused.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(General.secureScreenUnsupported.get<bool>(false), isTrue);
      c.onClose();
    });

    test('a device that honours the flag leaves no note behind', () async {
      // The answer belongs to a request. Carrying a stale refusal would make
      // a device that started honouring the flag look permanently broken.
      General.secureScreenUnsupported.set<bool>(true);
      ReaderKeys.secureScreen.set<bool>(true);

      final (c, _) = await open('/c-1');
      for (var i = 0; i < 10 && !c.secureApplied.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(General.secureScreenUnsupported.get<bool>(true), isFalse);
      c.onClose();
    });

    test('a stale secure answer cannot overwrite a newer one', () async {
      // Two toggles in flight: the older channel round trip must not land last
      // and describe a request that has since been replaced. These are a
      // privacy claim, so a wrong one tells the reader screenshots are blocked
      // when they are not. Found by `codeant-ai`.
      ReaderKeys.secureScreen.set<bool>(false);
      final (c, _) = await open('/c-1');

      // Turn on (which this fake refuses), then immediately off.
      final first = c.setSecure(true);
      final second = c.setSecure(false);
      await Future.wait([first, second]);

      expect(
        c.secureRefused.value,
        isFalse,
        reason: 'the latest request was an off, which cannot be refused',
      );
      expect(c.secureApplied.value, isFalse);
      c.onClose();
    });

    test('an applied secure flag reports applied and not refused', () async {
      ReaderKeys.secureScreen.set<bool>(true);

      final (c, _) = await open('/c-1');
      for (var i = 0; i < 10 && !c.secureApplied.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(c.secureApplied.value, isTrue);
      expect(c.secureRefused.value, isFalse);
      c.onClose();
    });

    test('the e-ink duration is read and clamped', () async {
      ReaderKeys.displayRefreshEnabled.set<bool>(true);
      ReaderKeys.displayRefreshDurationMs.set<int>(99999);

      final (c, _) = await open('/c-1');

      expect(c.einkFlash.value, isTrue);
      expect(c.einkFlashMs.value, 2000);
      c.onClose();
    });
  });

  test('loads pages and orders chapters ascending', () async {
    await seed();
    final (c, _) = await open('/c-2');

    expect(c.pages, hasLength(4));
    // Ascending, so Next means the next one to read. The details screen shows
    // newest first; inheriting that would make Next walk backwards.
    expect(c.chaptersInOrder.map((x) => x.number), [1, 2, 3]);
    expect(c.hasNext, isTrue);
    expect(c.hasPrevious, isTrue);
  });

  test('reaching the last page marks the chapter read', () async {
    await seed();
    final (c, _) = await open('/c-1');

    c.onPageChanged(2); // last of three
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final entry = (await library.find(_sourceId, _manga))!;
    final chapter = entry.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isTrue);
    expect(chapter.lastPageRead, 2);
    expect(chapter.totalPages, 3);
  });

  test('stopping short does not mark the chapter read', () async {
    await seed();
    final (c, _) = await open('/c-2');

    c.onPageChanged(1); // of four
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(chapter.read, isFalse);
    expect(chapter.lastPageRead, 1);
  });

  test('finishing a chapter reports it to AniList once', () async {
    await seed();
    final (c, _) = await open('/c-1');

    c.onPageChanged(2); // last of three
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    expect(reporter.calls, hasLength(1));
    expect(reporter.calls.single.chapterNumber, 1);
  });

  test('a chapter already read is not reported again', () async {
    // The guard this exists for. `onPageChanged` fires on every scroll, so a
    // chapter sitting at its last page would report itself on every twitch of
    // the finger — a mutation per frame at the end of every chapter.
    //
    // Checking `read` *before* the write is what makes it a transition; a
    // state check after it is always true and reports forever.
    await seed();
    final (c, _) = await open('/c-1');

    c.onPageChanged(2);
    await c.flush();
    await Future<void>.delayed(Duration.zero);
    expect(reporter.calls, hasLength(1));

    // Still on the last page, scrolling around.
    c.onPageChanged(1);
    await c.flush();
    await Future<void>.delayed(Duration.zero);
    c.onPageChanged(2);
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    expect(
      reporter.calls,
      hasLength(1),
      reason: 'the chapter was already read; nothing changed to report',
    );
  });

  test('stopping short reports nothing', () async {
    await seed();
    final (c, _) = await open('/c-2');

    c.onPageChanged(1); // of four
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    expect(reporter.calls, isEmpty);
  });

  test('opening a chapter reports nothing', () async {
    // Opening saves with `markRead: false` explicitly, so a one-page chapter
    // does not report itself for being glanced at.
    await seed();
    await open('/c-3');
    await Future<void>.delayed(Duration.zero);

    expect(reporter.calls, isEmpty);
  });

  test('reopening a finished chapter never marks it unread', () async {
    // The reader writes progress on every page change, so a chapter finished
    // earlier would otherwise flip back to unread the moment it was reopened
    // at page one.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-1',
      lastPageRead: 2,
      totalPages: 3,
      markRead: true,
    );

    final (c, _) = await open('/c-1');
    c.onPageChanged(0);
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isTrue);
  });

  test('an unfinished chapter resumes where it was left', () async {
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 2,
      totalPages: 4,
    );

    final (c, _) = await open('/c-2');

    expect(c.initialPage, 2);
    expect(c.page.value, 2);
  });

  test('a finished chapter restarts at the top, not on its last page', () async {
    // Reopening something you have read means re-reading it; dropping the user
    // on the final page looks broken.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-1',
      lastPageRead: 2,
      totalPages: 3,
      markRead: true,
    );

    final (c, _) = await open('/c-1');

    expect(c.initialPage, 0);
  });

  test('a stored position past the end is clamped, not crashed', () async {
    // A source can republish a chapter with fewer pages.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-3',
      lastPageRead: 40,
      totalPages: 41,
    );

    final (c, _) = await open('/c-3');

    expect(c.initialPage, 1, reason: 'the chapter now has two pages');
  });

  test('a webtoon scroll position is stored and restored', () async {
    // A page index is not enough in continuous mode: the user stops partway
    // down a strip. The screen previously computed a page index from the scroll
    // fraction and never restored anything, so webtoon resume did nothing at
    // all -- while the commit message claimed it worked.
    await seed();
    final (first, _) = await open('/c-2');
    first.onScroll(1840.5, 6000);
    first.onPageChanged(1);
    await first.flush();

    final stored = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(stored.currentOffset, 1840.5);
    expect(stored.maxOffset, 6000);

    final (second, _) = await open('/c-2');
    expect(second.initialOffset, 1840.5);
  });

  test('a finished chapter restarts at the top of the strip too', () async {
    await seed();
    final (first, _) = await open('/c-1');
    first.onScroll(900, 1000);
    first.onPageChanged(2); // last page -> read
    await first.flush();

    final (second, _) = await open('/c-1');
    expect(second.initialOffset, 0);
    expect(second.initialPage, 0);
  });

  test('paged reading does not erase a stored webtoon offset', () async {
    // updateChapterProgress takes nullable offsets; null means "not in
    // continuous mode" and must leave a previous webtoon position alone.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 1,
      totalPages: 4,
      currentOffset: 500,
      maxOffset: 2000,
    );

    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 2,
      totalPages: 4,
    );

    final stored = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(stored.currentOffset, 500);
    expect(stored.lastPageRead, 2);
  });

  test('opening a one-page chapter does not mark it read', () async {
    // Page 0 of 1 is also the last page, so an unguarded save on load would
    // finish a chapter the user has not looked at.
    await seed();
    final (c, _) = await open('/c-1', pages: {'/c-1': _pages(1)});

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isFalse);
    expect(c.pages, hasLength(1));
  });

  test('unnumbered extras sort after numbered chapters, not before', () async {
    // `?? 0` put every extra before chapter 1, so Next walked the extras first.
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _manga,
      manga: MManga(
        name: 'Example',
        chapters: [
          MChapter(url: '/extra', name: 'Omake'),
          MChapter(url: '/c-1', name: 'Chapter 1'),
          MChapter(url: '/c-2', name: 'Chapter 2'),
        ],
      ),
    );
    final (c, _) = await open('/c-1', pages: {'/c-1': _pages(2)});

    expect(c.chaptersInOrder.map((x) => x.url), ['/c-1', '/c-2', '/extra']);
  });

  test('next moves forward and saves the chapter being left', () async {
    await seed();
    final (c, _) = await open('/c-1');
    c.onPageChanged(1);

    await c.next();

    expect(c.currentChapterUrl.value, '/c-2');
    expect(c.pages, hasLength(4));
    final left = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(
      left.lastPageRead,
      1,
      reason: 'progress was flushed before the move',
    );
  });

  test('there is no next past the last chapter', () async {
    await seed();
    final (c, _) = await open('/c-3');

    expect(c.hasNext, isFalse);
    await c.next(); // must not throw

    expect(c.currentChapterUrl.value, '/c-3');
  });

  test(
    'an empty page list reads as a source failure, not an empty chapter',
    () async {
      // A blank reader would look like the app lost the images.
      await seed();
      final (c, _) = await open('/c-1', pages: {'/c-1': const []});

      expect(c.error.value, contains('no pages'));
      expect(c.pages, isEmpty);
    },
  );

  test('a failed page list reports the site', () async {
    await seed();
    final methods = _Methods(_row())..failWith = StateError('403');
    final c = ReaderController(
      sources: _Sources(methods, _row()),
      library: library,
      anilistProgress: _SpyReporter(),
      wakelock: _FakeWakelock(),
      screen: FakeScreenControls(),
      sourceId: _sourceId,
      mangaUrl: _manga,
      chapterUrl: '/c-1',
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.error.value, contains('site may be down'));
    expect(c.isLoading.value, isFalse);
  });

  group('reading from disk', () {
    late Directory downloads;

    setUp(() {
      downloads = Directory.systemTemp.createTempSync('otaku-reader-offline');
    });
    tearDown(() {
      if (downloads.existsSync()) downloads.deleteSync(recursive: true);
    });

    Future<void> markDownloaded(String chapterUrl, String path) =>
        library.setChapterLocalPath(
          sourceId: _sourceId,
          url: _manga,
          chapterUrl: chapterUrl,
          localPath: path,
        );

    test('a downloaded chapter reads from disk, not from the source', () async {
      await seed();
      for (final name in ['0001.jpg', '0002.png', '0003.webp']) {
        File(p.join(downloads.path, name)).writeAsBytesSync([0]);
      }
      await markDownloaded('/c-1', downloads.path);

      final (c, methods) = await open('/c-1');

      expect(c.isOffline.value, isTrue);
      expect(c.pages, hasLength(3));
      expect(methods.pageListCalls, isEmpty, reason: 'the site is not touched');
      expect(c.pages.map((x) => p.basename(x.url)), [
        '0001.jpg',
        '0002.png',
        '0003.webp',
      ]);
    });

    test('a file the downloader did not write is not a page', () async {
      // A `.nomedia`, or a thumbnail from a gallery app that scanned the
      // folder. It sorts ahead of `0001.jpg`, so without the filter it becomes
      // the broken first page of every downloaded chapter.
      await seed();
      File(p.join(downloads.path, '.nomedia')).writeAsBytesSync([0]);
      File(p.join(downloads.path, '0001.jpg')).writeAsBytesSync([0]);
      File(p.join(downloads.path, 'Thumbs.db')).writeAsBytesSync([0]);
      await markDownloaded('/c-1', downloads.path);

      final (c, _) = await open('/c-1');

      expect(c.pages.map((x) => p.basename(x.url)), ['0001.jpg']);
    });

    test('a stale pointer falls back to the source and is cleared', () async {
      // Storage cleared, or the folder moved. Falling back is only half an
      // answer: the details screen reads the same field and would go on
      // offering "delete" for a download that is not there.
      await seed();
      await markDownloaded('/c-1', p.join(downloads.path, 'gone'));

      final (c, methods) = await open('/c-1');

      expect(c.isOffline.value, isFalse);
      expect(c.pages, hasLength(3), reason: 'fetched from the source instead');
      expect(methods.pageListCalls, ['/c-1']);

      final entry = await library.find(_sourceId, _manga);
      final chapter = entry!.chapters.firstWhere((x) => x.url == '/c-1');
      expect(chapter.localPath, isNull);
    });

    test('a downloaded chapter that is empty is treated as stale', () async {
      await seed();
      await markDownloaded('/c-1', downloads.path);

      final (c, _) = await open('/c-1');

      expect(c.isOffline.value, isFalse);
      expect(c.pages, hasLength(3));
      final entry = await library.find(_sourceId, _manga);
      final chapter = entry!.chapters.firstWhere((x) => x.url == '/c-1');
      expect(chapter.localPath, isNull);
    });
  });

  group('keep the screen on', () {
    // The switch shipped writing `ReaderKeys.keepScreenOn` with nothing on the
    // other side, so a round-trip test would have passed the whole time it was
    // dead. These assert the *request*, which is the thing that was missing.

    test('asks for the wakelock when the setting is on', () async {
      await seed();
      ReaderKeys.keepScreenOn.set<bool>(true);

      await open('/c-1');

      expect(wakelock.enables, 1);
    });

    test('an unset key defaults to on', () async {
      // Absent is the state a fresh install is in, and it is a different state
      // from a stored `true` -- the KV tier answers null for it, and the
      // fallback is what decides.
      await seed();

      await open('/c-1');

      expect(wakelock.enables, 1);
    });

    test('never asks when the setting is off', () async {
      // The case AnymeX's shape gets wrong: it enables unconditionally in
      // onInit and corrects itself once preferences load, which holds the
      // screen awake against the user's choice for the width of that window.
      await seed();
      ReaderKeys.keepScreenOn.set<bool>(false);

      await open('/c-1');

      expect(wakelock.enables, 0);
    });

    test('releases it on close even when the setting is off', () async {
      // Unconditional on the way out. If the release were keyed on the setting
      // too, turning the switch off mid-chapter would strand a lock that had
      // already been taken.
      await seed();
      ReaderKeys.keepScreenOn.set<bool>(true);
      final (c, _) = await open('/c-1');
      ReaderKeys.keepScreenOn.set<bool>(false);

      c.onClose();
      await Future<void>.delayed(Duration.zero);

      expect(wakelock.disables, 1);
    });
  });

  group('show the page number', () {
    // The controller half only. Whether the pill actually reaches the screen is
    // asserted in reader_screen_test.dart, because a flag nothing renders is
    // the same defect one layer up.

    test('an unset key defaults to off, as AnymeX does', () async {
      await seed();

      final (c, _) = await open('/c-1');

      expect(c.showPageIndicator.value, isFalse);
    });

    test('follows the stored setting', () async {
      await seed();
      ReaderKeys.showPageIndicator.set<bool>(true);

      final (c, _) = await open('/c-1');

      expect(c.showPageIndicator.value, isTrue);
    });
  });

  group('the reading direction', () {
    // The reader honours four directions now, and every one of them arrives
    // through a stored enum index. That is the whole surface: a round-trip of
    // the key proves nothing -- it is exactly what passed the entire time the
    // two inert Settings switches shipped -- so these assert what the
    // *controller* ends up holding.

    for (final expected in ReadingDirection.values) {
      test('a stored ${expected.name} reaches the reader', () async {
        // The mutation guard for the clamp. `clamp(0, 1)` stood here: a
        // literal bound where an enum property belongs, so the two appended
        // members were pinned back to left-to-right while the Settings row --
        // which already clamped against `values.length` -- went on offering
        // them. Nothing failed, on either side.
        await seed();
        ReaderKeys.readingDirection.set<int>(expected.index);
        final (c, _) = await open('/c-1');

        expect(c.direction.value, expected);
      });
    }

    test(
      'an index no build has ever written falls back rather than throws',
      () async {
        // A row from a future build, or a corrupted one. Reading it happens
        // inside `onInit`, which has nobody to catch a RangeError.
        await seed();
        ReaderKeys.readingDirection.set<int>(99);
        final (c, _) = await open('/c-1');

        expect(c.direction.value, ReadingDirection.values.last);
      },
    );

    test('each direction names an axis and a sign', () {
      // Mechanism-independent, and it is the pair every call site consumes:
      // one wrong entry turns a right-to-left manga into a vertical one with
      // no other symptom.
      expect(ReadingDirection.leftToRight.axis, Axis.horizontal);
      expect(ReadingDirection.rightToLeft.axis, Axis.horizontal);
      expect(ReadingDirection.topToBottom.axis, Axis.vertical);
      expect(ReadingDirection.bottomToTop.axis, Axis.vertical);

      expect(ReadingDirection.leftToRight.reversed, isFalse);
      expect(ReadingDirection.rightToLeft.reversed, isTrue);
      expect(ReadingDirection.topToBottom.reversed, isFalse);
      expect(ReadingDirection.bottomToTop.reversed, isTrue);
    });

    test('the first two members keep the indices already on disk', () {
      // AnymeX's own enum is `{up, down, left, right}`, and taking that order
      // would have re-pointed every stored value: a `0` written by this app
      // means left-to-right, and there are users holding one. New members are
      // appended for that reason, and this is what says so out loud.
      expect(ReadingDirection.leftToRight.index, 0);
      expect(ReadingDirection.rightToLeft.index, 1);
    });

    test('the two layouts do not share a direction', () async {
      // The departure from AnymeX, which keeps one value and then
      // force-overrides it to `down` whenever its webtoon detector fires.
      // Sharing here would be worse: the stored default is left-to-right, so
      // every existing webtoon reader would have come back from the upgrade
      // scrolling sideways.
      await seed();
      ReaderKeys.readingDirection.set<int>(ReadingDirection.rightToLeft.index);
      ReaderKeys.webtoonDirection.set<int>(ReadingDirection.topToBottom.index);
      final (c, _) = await open('/c-1');

      expect(c.direction.value, ReadingDirection.rightToLeft);
      expect(c.webtoonDirection.value, ReadingDirection.topToBottom);
    });

    test(
      'with nothing stored each layout starts where its readers read',
      () async {
        // A fresh install. One shared default cannot be right for both: a long
        // strip read sideways is as wrong as a manga read downwards.
        await seed();
        final (c, _) = await open('/c-1');

        expect(c.direction.value, ReadingDirection.leftToRight);
        expect(c.webtoonDirection.value, ReadingDirection.topToBottom);
        expect(
          ReadingDirection.defaultFor(ReadingLayout.paged),
          ReadingDirection.leftToRight,
        );
        expect(
          ReadingDirection.defaultFor(ReadingLayout.webtoon),
          ReadingDirection.topToBottom,
        );
      },
    );

    test('activeDirection is whichever layout is on screen', () async {
      await seed();
      ReaderKeys.readingDirection.set<int>(ReadingDirection.rightToLeft.index);
      ReaderKeys.webtoonDirection.set<int>(ReadingDirection.bottomToTop.index);
      final (c, _) = await open('/c-1');

      c.setLayout(ReadingLayout.paged);
      expect(c.activeDirection, ReadingDirection.rightToLeft);

      c.setLayout(ReadingLayout.webtoon);
      expect(c.activeDirection, ReadingDirection.bottomToTop);
    });

    test(
      'setActiveDirection writes the key its layout reads, and only that one',
      () async {
        // The reader's own control edits "the direction", and which key that is
        // belongs with `activeDirection` rather than with the button. Splitting
        // that knowledge is how the control comes to write one key while the
        // reader renders the other.
        await seed();
        final (c, _) = await open('/c-1');

        c.setLayout(ReadingLayout.webtoon);
        c.setActiveDirection(ReadingDirection.rightToLeft);

        expect(
          ReaderKeys.webtoonDirection.get<int>(0),
          ReadingDirection.rightToLeft.index,
        );
        expect(
          ReaderKeys.readingDirection.get<int?>(),
          isNull,
          reason: 'the paged direction was never touched',
        );
      },
    );

    test('the quick cycle reaches every direction and wraps', () async {
      // The reader's control cycles rather than toggles, because there are
      // four. A cycle that skipped one would leave a direction reachable only
      // from Settings, and a cycle that did not wrap would strand the reader
      // on the last.
      var direction = ReadingDirection.values.first;
      final seen = <ReadingDirection>{direction};
      for (var i = 0; i < ReadingDirection.values.length - 1; i++) {
        direction = direction.next;
        seen.add(direction);
      }

      expect(seen, ReadingDirection.values.toSet());
      expect(direction.next, ReadingDirection.values.first);
    });

    test('every direction is named, in one place', () {
      // On the enum rather than in either screen, so the reader's tooltip and
      // the Settings row cannot disagree -- and so a member added later cannot
      // be labelled in one and left blank in the other.
      for (final d in ReadingDirection.values) {
        expect(d.label.trim(), isNotEmpty, reason: d.name);
        expect(d.shortLabel.trim(), isNotEmpty, reason: d.name);
      }
      expect(
        ReadingDirection.values.map((d) => d.label).toSet(),
        hasLength(ReadingDirection.values.length),
      );
    });
  });
}
