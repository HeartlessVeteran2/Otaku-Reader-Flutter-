import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_status.dart';

import 'helpers/isar_test_env.dart';

const _sourceId = 424242;
const _url = '/manga/example';

MChapter _ch(String url, {String? name}) =>
    MChapter(url: url, name: name ?? 'Chapter ${url.split('-').last}');

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async => env = await IsarTestEnv.open('lib', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final repo = LibraryRepositoryImpl();

  Future<MangaEntry> save(MManga manga) =>
      repo.upsertFromSource(sourceId: _sourceId, url: _url, manga: manga);

  test('the source key is the id itself, and converts straight back', () {
    // The Kotlin app hashed this and calls the resulting one-way mapping its
    // highest-impact bug ever.
    final key = LibraryRepositoryImpl.keyFor(_sourceId);
    expect(key, '424242');
    expect(LibraryRepositoryImpl.sourceIdFrom(key), _sourceId);
  });

  test('saving from a source does not add to the library', () async {
    // Opening a detail page is not the same as adding the manga, and
    // conflating the two silently fills the library with everything opened.
    final entry = await save(MManga(name: 'Example'));

    expect(entry.favorite, isFalse);
    expect(await repo.favorites(), isEmpty);
  });

  test('opening the same manga twice does not create a second row', () async {
    await save(MManga(name: 'Example'));
    await save(MManga(name: 'Example'));

    expect(db.isar.mangaEntrys.countSync(), 1);
  });

  test('read state survives a chapter refresh', () async {
    // The failure this guards is immediate and irreversible from the user's
    // side: a refresh that resets every chapter to unread.
    await save(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1'), _ch('/c-2'), _ch('/c-3')],
      ),
    );
    await repo.setChapterRead(_sourceId, _url, '/c-1', true);
    await repo.setChapterRead(_sourceId, _url, '/c-2', true);

    // The source re-lists the same chapters, plus a new one.
    await save(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1'), _ch('/c-2'), _ch('/c-3'), _ch('/c-4')],
      ),
    );

    final entry = (await repo.find(_sourceId, _url))!;
    final read = {for (final c in entry.chapters) c.url: c.read};
    expect(read, {'/c-1': true, '/c-2': true, '/c-3': false, '/c-4': false});
  });

  test(
    'a refresh updates source-owned fields but not user-owned ones',
    () async {
      await save(
        MManga(
          name: 'Example',
          chapters: [_ch('/c-1', name: 'Ch. 1')],
        ),
      );
      await repo.setChapterRead(_sourceId, _url, '/c-1', true);

      await save(
        MManga(
          name: 'Example',
          chapters: [
            MChapter(
              url: '/c-1',
              name: 'Chapter 1: The Beginning',
              scanlator: 'Team',
            ),
          ],
        ),
      );

      final chapter = (await repo.find(_sourceId, _url))!.chapters.single;
      expect(
        chapter.name,
        'Chapter 1: The Beginning',
        reason: 'source owns this',
      );
      expect(chapter.scanlator, 'Team');
      expect(chapter.read, isTrue, reason: 'the user owns this');
    },
  );

  test('a read chapter the source has dropped is kept', () async {
    // Sites drop and re-add chapters constantly. Dropping the row would erase
    // the fact that it was read.
    await save(MManga(name: 'Example', chapters: [_ch('/c-1'), _ch('/c-2')]));
    await repo.setChapterRead(_sourceId, _url, '/c-1', true);

    await save(MManga(name: 'Example', chapters: [_ch('/c-2')]));

    final urls = (await repo.find(_sourceId, _url))!.chapters.map((c) => c.url);
    expect(urls, containsAll(['/c-1', '/c-2']));
  });

  test('an unread chapter the source has dropped is not kept', () async {
    await save(MManga(name: 'Example', chapters: [_ch('/c-1'), _ch('/c-2')]));

    await save(MManga(name: 'Example', chapters: [_ch('/c-2')]));

    final urls = (await repo.find(_sourceId, _url))!.chapters.map((c) => c.url);
    expect(urls, ['/c-2']);
  });

  test('a blank field from the source is a gap, not an erasure', () async {
    // Detail pages routinely omit an author the listing carried. Letting the
    // blank win wipes good data on every refresh.
    await save(
      MManga(name: 'Example', author: 'Kishimoto', description: 'A story'),
    );

    await save(MManga(name: 'Example', author: null, description: '   '));

    final entry = (await repo.find(_sourceId, _url))!;
    expect(entry.author, 'Kishimoto');
    expect(entry.description, 'A story');
  });

  test('an unknown status does not overwrite a known one', () async {
    await save(MManga(name: 'Example', status: Status.ongoing));

    await save(MManga(name: 'Example', status: Status.unknown));

    expect((await repo.find(_sourceId, _url))!.status, Status.ongoing.index);
  });

  test('favorite toggles and lists', () async {
    await save(MManga(name: 'Example'));

    expect(await repo.toggleFavorite(_sourceId, _url), isTrue);
    expect((await repo.favorites()).map((e) => e.url), [_url]);

    expect(await repo.toggleFavorite(_sourceId, _url), isFalse);
    expect(await repo.favorites(), isEmpty);
  });

  group('chapter number parsing', () {
    final parse = LibraryRepositoryImpl.parseChapterNumber;

    test('plain and prefixed forms', () {
      expect(parse('Chapter 12'), 12);
      expect(parse('Ch. 12'), 12);
      expect(parse('ch12'), 12);
      expect(parse('12'), 12);
    });

    test('fractional chapters are real', () {
      expect(parse('Chapter 12.5'), 12.5);
    });

    test('a volume prefix does not win over the chapter', () {
      expect(parse('Vol.2 Ch.5'), 5);
      expect(parse('Volume 3 Chapter 41'), 41);
    });

    test('a title with no number yields null, not a misleading zero', () {
      expect(parse('Extra: Behind the scenes'), isNull);
      expect(parse(null), isNull);
    });
  });
}
