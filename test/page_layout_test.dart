import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/features/reader/display/page_layout.dart';

/// Long-strip detection and page sizing.
void main() {
  MangaEntry withGenres(List<String> genres) => MangaEntry()..genres = genres;

  group('long-strip detection', () {
    test('the markers AnymeX uses, in any casing', () {
      for (final genre in [
        'Webtoon',
        'WEBTOON',
        'Manhwa',
        'Long Strip',
        'long-strip',
        'Full Color, Long Strip',
      ]) {
        expect(readsAsLongStrip(withGenres([genre])), isTrue, reason: genre);
      }
    });

    test('manhua is deliberately not a marker', () {
      // Manhwa is close to universally long-strip; manhua is a mixture. The
      // same rule would flip a substantial number of page-per-page series into
      // a continuous reader, and a wrong guess changes how every page turn
      // behaves rather than how the page looks.
      expect(readsAsLongStrip(withGenres(['Manhua'])), isFalse);
    });

    test('ordinary manga genres are not markers', () {
      expect(
        readsAsLongStrip(withGenres(['Action', 'Seinen', 'Drama'])),
        isFalse,
      );
      expect(readsAsLongStrip(withGenres(const [])), isFalse);
    });

    test('one marker among many genres is enough', () {
      expect(
        readsAsLongStrip(withGenres(['Action', 'Webtoon', 'Romance'])),
        isTrue,
      );
    });
  });

  group('page sizing', () {
    test('the gap disappears rather than going to zero', () {
      // Same rule as the dim veil and the e-ink flash: at zero, remove the
      // effect rather than render an empty box of it.
      const spaced = PageLayout(
        fitToScreen: true,
        widthFactor: 1,
        spaced: true,
      );
      const flush = PageLayout(
        fitToScreen: true,
        widthFactor: 1,
        spaced: false,
      );
      expect(spaced.gap, greaterThan(0));
      expect(flush.gap, 0);
    });
  });
}
