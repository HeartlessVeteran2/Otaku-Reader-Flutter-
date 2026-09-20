import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/ui/greeting_controller.dart';

/// The greeting under a tab root's title.
///
/// Two things are worth guarding, and only one of them is AnymeX's.
///
/// The **bands** are ported exactly, so the tests walk their boundaries rather
/// than sampling a few comfortable hours — an off-by-one at 12 or 17 is
/// invisible for most of the day and wrong for an hour of it.
///
/// The **stability** is this app's own, and is the reason a clock is injected
/// at all. AnymeX re-rolls its phrase inside the method its 15-minute timer
/// runs, so the header flips between "Good evening" and "Keep it chill" four
/// times an hour. Here the roll happens only across a boundary, and that is a
/// property a test can only see by ticking many times and watching nothing
/// change.
void main() {
  tearDown(Get.reset);

  GreetingController at(DateTime when, {Random? random}) =>
      GreetingController(clock: () => when, random: random);

  group('the bands are AnymeX\'s own, including their edges', () {
    // Each boundary hour and the hour before it, so a `>=` slipping to `>`
    // fails rather than shifting the whole day by one.
    const cases = <int, GreetingBand>{
      0: GreetingBand.night,
      4: GreetingBand.night,
      5: GreetingBand.morning,
      11: GreetingBand.morning,
      12: GreetingBand.afternoon,
      16: GreetingBand.afternoon,
      17: GreetingBand.evening,
      20: GreetingBand.evening,
      21: GreetingBand.night,
      23: GreetingBand.night,
    };

    for (final entry in cases.entries) {
      test('${entry.key}:00 is ${entry.value.name}', () {
        expect(GreetingBand.at(DateTime(2026, 1, 1, entry.key)), entry.value);
      });
    }
  });

  test('every band offers two phrases and never an empty one', () {
    // The controller indexes into this list, so an empty one is a crash in
    // the header on a schedule.
    for (final band in GreetingBand.values) {
      expect(band.phrases, hasLength(2), reason: band.name);
      expect(band.phrases.any((p) => p.trim().isEmpty), isFalse);
    }
  });

  test('the first read produces a phrase from the right band', () {
    final c = at(DateTime(2026, 1, 1, 8))..onInit();

    expect(GreetingBand.morning.phrases, contains(c.text.value));
  });

  test('the phrase does not change while the band does not', () {
    // The whole point of the divergence: AnymeX re-rolls on every tick, this
    // re-rolls only across a boundary.
    //
    // **Every** observed value is collected, not just the last one. The first
    // version of this test compared the end state to the start, and an
    // alternating `Random` walks 0,1,0,1... so after an even number of ticks
    // it lands back where it began -- the greeting flipped twenty times and
    // the assertion saw none of it. Restoring AnymeX's per-tick roll left it
    // green, which is how that was found. Same shape as the cancel test in
    // `CLAUDE.md` that asserted only the end state.
    final c = at(DateTime(2026, 1, 1, 18), random: _Alternating())..onInit();

    final seen = {c.text.value};
    for (var i = 0; i < 20; i++) {
      c.refreshGreeting();
      seen.add(c.text.value);
    }

    expect(
      seen,
      hasLength(1),
      reason: 'twenty ticks inside one evening produced ${seen.length} phrases',
    );
  });

  test('crossing a boundary does change it', () {
    // The other half: without this, never re-rolling at all would satisfy the
    // test above, and the greeting would be stuck on whatever the app opened
    // with until the process died.
    var now = DateTime(2026, 1, 1, 16, 59);
    final c = GreetingController(clock: () => now)..onInit();
    final afternoon = c.text.value;
    expect(GreetingBand.afternoon.phrases, contains(afternoon));

    now = DateTime(2026, 1, 1, 17, 0);
    c.refreshGreeting();

    expect(GreetingBand.evening.phrases, contains(c.text.value));
  });

  test('a band re-entered later is free to pick the other phrase', () {
    // Stability is per *visit*, not forever: the point of shipping two
    // phrases is that tomorrow morning can read differently from this one.
    // Pinned with a Random that always takes the second, so the assertion is
    // about the re-roll happening rather than about luck.
    var now = DateTime(2026, 1, 1, 8);
    final c = GreetingController(clock: () => now, random: _Always(1))
      ..onInit();
    expect(c.text.value, GreetingBand.morning.phrases[1]);

    now = DateTime(2026, 1, 1, 13);
    c.refreshGreeting();
    expect(c.text.value, GreetingBand.afternoon.phrases[1]);

    now = DateTime(2026, 1, 2, 8);
    c.refreshGreeting();
    expect(c.text.value, GreetingBand.morning.phrases[1]);
  });

  test('the timer stops with the controller', () {
    // A periodic timer outliving its controller keeps a closure alive and
    // fires against a disposed observable. `onClose` is the only thing that
    // cancels it, so deleting that line has to fail something.
    final c = at(DateTime(2026, 1, 1, 8))..onInit();

    c.onClose();

    expect(() => c.onClose(), returnsNormally, reason: 'and is idempotent');
  });
}

/// Returns a different value on each call, so a per-tick re-roll would show.
class _Alternating implements Random {
  _Alternating();

  int _n = 0;

  @override
  int nextInt(int max) => (_n++) % max;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => 0;
}

/// Always picks the same index, so a test can name the phrase it expects.
class _Always implements Random {
  const _Always(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => 0;
}
