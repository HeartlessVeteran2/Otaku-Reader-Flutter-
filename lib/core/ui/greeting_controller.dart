import 'dart:async';
import 'dart:math';

import 'package:get/get.dart';

/// The time-of-day band a greeting belongs to.
///
/// Named rather than expressed as bare hour arithmetic at the call site,
/// because the *band* is what the stability rule below turns on: the phrase
/// may only be re-rolled when this changes.
enum GreetingBand {
  morning,
  afternoon,
  evening,
  night;

  /// AnymeX's own boundaries (`greeting.dart`), kept exactly: 5, 12, 17, 21.
  static GreetingBand at(DateTime when) {
    final hour = when.hour;
    if (hour >= 5 && hour < 12) return GreetingBand.morning;
    if (hour >= 12 && hour < 17) return GreetingBand.afternoon;
    if (hour >= 17 && hour < 21) return GreetingBand.evening;
    return GreetingBand.night;
  }

  /// The two phrases AnymeX picks between for this band, in its own order.
  List<String> get phrases => switch (this) {
    GreetingBand.morning => const ['Good morning', 'Rise and shine'],
    GreetingBand.afternoon => const ['Good afternoon', 'Happy snacking'],
    GreetingBand.evening => const ['Good evening', 'Keep it chill'],
    GreetingBand.night => const ['Goodnight', "You're up late"],
  };
}

/// The greeting under the title on a tab root.
///
/// Ported from AnymeX's `GreetingController`, with the same four bands and the
/// same eight phrases, and **one deliberate behavioural change**.
///
/// AnymeX calls `random.nextBool()` inside the method its 15-minute timer
/// runs, so the phrase is re-rolled on *every tick*: a reader sitting in one
/// evening watches the header flip between "Good evening" and "Keep it chill"
/// four times an hour, for no reason they can perceive. That reads as the app
/// glitching rather than as personality.
///
/// Here the roll happens only when the **band** changes. Within one evening
/// the phrase is fixed; across days it still varies, which is the whole point
/// of having two of them. The timer therefore exists to notice a *boundary*,
/// not to shuffle text.
class GreetingController extends GetxController {
  GreetingController({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  /// Injected so a test can stand at 04:59 and then at 05:00 without waiting.
  /// Every band boundary is otherwise unreachable except by running the suite
  /// at that hour, which is the kind of test that passes for the wrong reason
  /// most of the day.
  final DateTime Function() _clock;
  final Random _random;

  /// How often the band is re-checked. A boundary can be missed by at most
  /// this much, which is invisible for a greeting and is AnymeX's own figure.
  static const tick = Duration(minutes: 15);

  final text = ''.obs;

  /// The band the current phrase was chosen for. Null until the first read,
  /// so `onInit` always rolls once.
  GreetingBand? _band;

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    refreshGreeting();
    _timer = Timer.periodic(tick, (_) => refreshGreeting());
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  /// Re-reads the clock and re-rolls **only** across a band boundary.
  ///
  /// Not named `refresh`: `GetxController` already has one from the notifier
  /// mixin and GetX calls it internally to rebuild listeners, so shadowing it
  /// would re-roll the greeting every time the framework wanted a repaint.
  void refreshGreeting() {
    final band = GreetingBand.at(_clock());
    if (band == _band) return;
    _band = band;
    final phrases = band.phrases;
    text.value = phrases[_random.nextInt(phrases.length)];
  }
}
