import 'package:otaku_reader/data/isar/manga_entry.dart';

/// Whether a series reads as one long strip rather than as pages.
///
/// **Metadata, not measurement.** AnymeX decides this from the media's format,
/// genres and tags, and that is the right shape: it is knowable before a
/// single image has been fetched, so the reader opens in the correct layout
/// rather than switching under the reader once the first page has loaded.
/// Measuring the first page's aspect ratio is the obvious alternative and is
/// worse twice over — it needs a decoded image to decide, and a long-strip
/// chapter can legitimately open on a short title panel.
///
/// The vocabulary is AnymeX's, minus one addition it does not make and I am
/// not making either: **manhua is deliberately absent.** Manhwa is close to
/// universally long-strip, so the genre is a reliable signal; manhua is a
/// mixture of long-strip and paged, so the same rule would flip a substantial
/// number of page-per-page series into a continuous reader. A wrong guess here
/// is not cosmetic — it changes how every page turn behaves.
bool readsAsLongStrip(MangaEntry entry) {
  const markers = ['webtoon', 'manhwa', 'long strip', 'long-strip'];
  for (final genre in entry.genres) {
    final lower = genre.toLowerCase();
    if (markers.any(lower.contains)) return true;
  }
  return false;
}

/// How a page is sized inside the reader.
///
/// One object rather than four arguments threaded through two builders,
/// because the paged and continuous bodies have already diverged once in this
/// file's history and each reached for the key it happened to want — which is
/// the defect `activeDirection` exists to prevent, one layer down.
class PageLayout {
  const PageLayout({
    required this.fitToScreen,
    required this.widthFactor,
    required this.spaced,
  });

  /// Fill the available width, letting the page run past the screen's height.
  ///
  /// Off shows the whole page at its own aspect ratio. In a **paged** reader
  /// that is the difference between a page you scan and a page you see all of;
  /// in a strip it decides whether a wide double-spread is shrunk to fit or
  /// cropped to the column.
  final bool fitToScreen;

  /// A share of the viewport's width, in continuous mode only.
  ///
  /// **Narrows, never widens**, and that is a departure from AnymeX, whose
  /// slider runs 1.0-2.5. The reason is measured rather than stylistic: the
  /// paged body wraps every page in an `InteractiveViewer`, and the continuous
  /// body does not — a strip is already a scroll gesture and an
  /// `InteractiveViewer` around a `ListView` fights it. So a factor above 1
  /// would push the page past the viewport with no way to reach the part now
  /// off screen. Narrowing has no such failure and is the case a phone-shaped
  /// app actually has: a full-width strip on a tablet or in landscape is a
  /// column of text too wide to read.
  final double widthFactor;

  /// A gap between pages in continuous mode.
  final bool spaced;

  /// Vertical padding between strip pages. Zero when [spaced] is off, so the
  /// widget disappears rather than rendering a zero-height box — the same rule
  /// the dim veil and the e-ink flash follow.
  double get gap => spaced ? 8 : 0;
}
