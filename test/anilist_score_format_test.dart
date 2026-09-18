import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/anilist/anilist_auth.dart';

void main() {
  group('the ranges are AniList\'s, not ours', () {
    // Pinned against the live schema's own descriptions, read by introspecting
    // the endpoint rather than recalled:
    //
    //   POINT_100        "An integer from 0-100"
    //   POINT_10_DECIMAL "A float from 0-10 with 1 decimal place"
    //   POINT_10         "An integer from 0-10"
    //   POINT_5          "An integer from 0-5. Should be represented in Stars"
    //   POINT_3          "An integer from 0-3. Should be represented in
    //                     Smileys. 0 => No Score, 1 => :(, 2 => :|, 3 => :)"
    //
    // This is the contract a wrong guess writes 8.5/100 against, so it is
    // asserted rather than assumed.
    test('each format carries the range its schema description states', () {
      expect(ScoreFormat.point100.max, 100);
      expect(ScoreFormat.point100.decimals, 0);

      expect(ScoreFormat.point10Decimal.max, 10);
      expect(ScoreFormat.point10Decimal.decimals, 1);

      expect(ScoreFormat.point10.max, 10);
      expect(ScoreFormat.point10.decimals, 0);

      expect(ScoreFormat.point5.max, 5);
      expect(ScoreFormat.point5.decimals, 0);

      expect(ScoreFormat.point3.max, 3);
      expect(ScoreFormat.point3.decimals, 0);
    });

    test('divisions put every slider stop on a legal score', () {
      // A slider whose divisions do not match the grid can land between two
      // values AniList accepts, and the write is then rounded by somebody
      // else's rules.
      expect(ScoreFormat.point100.divisions, 100);
      expect(ScoreFormat.point10Decimal.divisions, 100);
      expect(ScoreFormat.point10.divisions, 10);
      expect(ScoreFormat.point5.divisions, 5);
      expect(ScoreFormat.point3.divisions, 3);
    });
  });

  group('clampScore', () {
    test('snaps a whole-number format onto whole numbers', () {
      expect(ScoreFormat.point10.clampScore(8.4), 8);
      expect(ScoreFormat.point10.clampScore(8.6), 9);
      expect(ScoreFormat.point5.clampScore(3.5), 4);
    });

    test('keeps one decimal place for POINT_10_DECIMAL', () {
      expect(ScoreFormat.point10Decimal.clampScore(8.46), 8.5);
      expect(ScoreFormat.point10Decimal.clampScore(8.0), 8.0);
    });

    test('brings a score from another format back onto this scale', () {
      // The case this exists for. A row is fetched with `score(format:)` as
      // the profile read *then*; the editor opens as it reads *now*. Change
      // the setting from POINT_100 to POINT_5 in between and the seed is an 85
      // on a five-star input — a value with no position to render at, which
      // without this leaves the editor unable to draw the row it opened on.
      expect(ScoreFormat.point5.clampScore(85), 5);
      expect(ScoreFormat.point3.clampScore(9), 3);
      expect(ScoreFormat.point100.clampScore(-4), 0);
    });
  });

  group('format', () {
    test('drops a pointless trailing decimal but keeps a real one', () {
      // A ten-point user who scored something 8 should see "8", not "8.0";
      // an 8.5 keeps its half.
      expect(ScoreFormat.point10Decimal.format(8), '8');
      expect(ScoreFormat.point10Decimal.format(8.5), '8.5');
      expect(ScoreFormat.point100.format(85), '85');
    });
  });

  group('parse', () {
    test('an unrecognised format falls back rather than throwing', () {
      // AniList adding an enum member must not stop a sign-in.
      expect(ScoreFormat.parse('POINT_7'), ScoreFormat.point10Decimal);
      expect(ScoreFormat.parse(null), ScoreFormat.point10Decimal);
      expect(ScoreFormat.parse('POINT_5'), ScoreFormat.point5);
    });
  });
}
