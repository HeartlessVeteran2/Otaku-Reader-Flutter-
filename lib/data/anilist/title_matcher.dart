import 'package:otaku_reader/domain/model/anilist_media.dart';

/// One AniList candidate and how well it matches the title we searched for.
class TitleMatch {
  const TitleMatch({required this.media, required this.score});

  final AniListMedia media;

  /// 0..1. 1.0 is an exact match once both titles are normalised.
  final double score;

  /// Whether this match is safe to store without asking the user.
  ///
  /// Below this, **nothing is persisted and nothing renders.** A wrong synopsis
  /// and wrong tags look exactly as authoritative as right ones, so a bad
  /// auto-match is worse than no match at all — the user has no way to tell it
  /// is wrong. The recourse is a manual picker, not a lower bar.
  bool get isConfident => score >= acceptThreshold;

  static const acceptThreshold = 0.87;
}

/// Matches a source's manga title against AniList search results.
///
/// Source titles are messy in predictable ways: scanlation group suffixes,
/// "(Official)", "[Colored]", language markers, and a season or part number
/// that AniList folds into one entry. Normalisation handles those; the
/// similarity score handles the rest.
class TitleMatcher {
  const TitleMatcher._();

  /// Picks the best candidate, or null when the list is empty.
  ///
  /// Callers must still check [TitleMatch.isConfident] — this returns the best
  /// available, which on a bad search is still bad.
  static TitleMatch? best(String sourceTitle, List<AniListMedia> candidates) {
    final needle = normalise(sourceTitle);
    if (needle.isEmpty) return null;

    TitleMatch? bestSoFar;
    for (final media in candidates) {
      var score = 0.0;
      for (final title in media.titles.all) {
        final candidate = similarity(needle, normalise(title));
        if (candidate > score) score = candidate;
      }
      if (bestSoFar == null || score > bestSoFar.score) {
        bestSoFar = TitleMatch(media: media, score: score);
      }
    }
    return bestSoFar;
  }

  /// Strips the decoration that source sites add and AniList does not carry.
  static String normalise(String input) {
    var s = input.toLowerCase();

    // Bracketed asides: "[Colored]", "(Official)", "(Doujinshi)".
    //
    // Only when something survives. Some titles are *entirely* bracketed --
    // AniList's real name for Oshi no Ko is "[Oshi no Ko]", brackets included --
    // and stripping those left an empty string that scored 0 against itself.
    final unbracketed = s
        .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), ' ')
        .trim();
    if (unbracketed.isNotEmpty) s = unbracketed;

    // Trailing language/format markers some sites append, anchored to the end.
    //
    // Unanchored, this deleted the word wherever it appeared — so "Raw Hero"
    // and "Hero" normalised to the same string and scored an exact match. Only
    // decoration a site *appends* is safe to drop, and repeating the pass
    // handles more than one ("... Manga RAW").
    final marker = RegExp(
      r'[\s\-_]*\b(manga|manhwa|manhua|webtoon|raw|official|english|indonesia)\b\s*$',
    );
    var trimmed = s.replaceFirst(marker, '').trim();
    while (trimmed.isNotEmpty && trimmed != s) {
      s = trimmed;
      trimmed = s.replaceFirst(marker, '').trim();
    }

    // Punctuation to spaces rather than nothing: "Re:Zero" must not become
    // "rezero" while AniList's "Re: Zero" becomes "re zero".
    //
    // Unicode-aware, not an ASCII allowlist plus one CJK range. Hangul sits at
    // U+AC00 and Cyrillic at U+0400, both outside that range, so a Korean or
    // Russian title was stripped to nothing and could never match — in an app
    // whose second word is "manhwa".
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');

    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Sørensen–Dice on character bigrams, 0..1.
  ///
  /// Chosen over edit distance because it is insensitive to word order and to a
  /// missing or extra word, which is exactly how source titles differ from
  /// AniList's — and it needs no dependency.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    // A one-character title has no bigrams; fall back to equality, already
    // handled above, so anything reaching here scores 0.
    if (a.length < 2 || b.length < 2) return 0;

    final pairsA = _bigrams(a);
    final pairsB = _bigrams(b);
    final total = pairsA.length + pairsB.length;
    if (total == 0) return 0;

    // Multiset intersection: consume each match so a repeated bigram cannot be
    // counted twice against a single occurrence.
    final remaining = [...pairsB];
    var hits = 0;
    for (final pair in pairsA) {
      final index = remaining.indexOf(pair);
      if (index >= 0) {
        remaining.removeAt(index);
        hits++;
      }
    }
    return 2 * hits / total;
  }

  static List<String> _bigrams(String s) => [
    for (var i = 0; i < s.length - 1; i++) s.substring(i, i + 2),
  ];
}
