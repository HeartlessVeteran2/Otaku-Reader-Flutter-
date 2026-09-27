/// How often the library refreshes itself.
///
/// Persisted by `index`, so this may only be **appended to** — the rule
/// `ReadingDirection` and `ReaderOrientation` already carry, and the one
/// `int status = 5` is in the mistakes table for.
enum UpdateInterval {
  /// Never on its own. The Updates tab's pull-to-refresh still works, so this
  /// is "don't crawl my sources without me", not "turn the feature off".
  manual,
  every6Hours,
  every12Hours,
  daily,
  every2Days,
  weekly;

  /// Null for [manual], which is what makes "never due" fall out of the
  /// arithmetic rather than needing a special case at every call site.
  Duration? get period => switch (this) {
    UpdateInterval.manual => null,
    UpdateInterval.every6Hours => const Duration(hours: 6),
    UpdateInterval.every12Hours => const Duration(hours: 12),
    UpdateInterval.daily => const Duration(days: 1),
    UpdateInterval.every2Days => const Duration(days: 2),
    UpdateInterval.weekly => const Duration(days: 7),
  };

  String get label => switch (this) {
    UpdateInterval.manual => 'Only when I ask',
    UpdateInterval.every6Hours => 'Every 6 hours',
    UpdateInterval.every12Hours => 'Every 12 hours',
    UpdateInterval.daily => 'Daily',
    UpdateInterval.every2Days => 'Every 2 days',
    UpdateInterval.weekly => 'Weekly',
  };
}

/// Why a scheduled refresh did or did not run.
///
/// Four answers rather than a bool, for the reason this codebase already
/// records about the AniList list lookup: they stop rendering the same the
/// moment anything reports them. "Not due yet" is the quiet ordinary case;
/// "waiting for Wi-Fi" is something the user can act on, and is the one that
/// otherwise looks identical to the feature being broken.
enum UpdateDecision {
  run,
  notDue,
  disabled,
  waitingForWifi,

  /// A refresh was already in flight, so this one was not started.
  ///
  /// Distinct from [run] because the caller is told what happened, and from
  /// [notDue] because the schedule *was* due. Two resume events can both pass
  /// the due check before either stamps the last check — the second used to
  /// answer `run` while `refreshLibrary` silently dropped it on its own
  /// in-flight guard. Found by `codeant-ai`; the same "busy is not refused"
  /// distinction the AniList save already makes.
  alreadyRunning;

  bool get shouldRun => this == UpdateDecision.run;
}

/// Decides whether the library is due a refresh.
///
/// **A pure function, deliberately.** Everything it needs is an argument, so
/// the whole policy is testable without a clock, a database, a network or a
/// platform channel — which matters because the alternative shape (a method
/// on a controller reading keys and plugins itself) is the shape that let two
/// Settings switches ship here writing keys nothing read.
///
/// The caller supplies [now] rather than this reading `DateTime.now()`, for
/// the same reason the greeting's clock is injected: every boundary is
/// otherwise unreachable except by running the suite at that hour.
UpdateDecision shouldRefreshLibrary({
  required UpdateInterval interval,
  required DateTime? lastCheck,
  required DateTime now,
  required bool wifiOnly,
  required bool onWifi,
}) {
  final period = interval.period;
  if (period == null) return UpdateDecision.disabled;

  // Checked **before** the network, on purpose. A library that has never been
  // refreshed is due whatever the connection is, and reporting "waiting for
  // Wi-Fi" for a schedule that is not due yet would put a banner on screen
  // about a refresh nobody was waiting for.
  if (lastCheck != null && now.difference(lastCheck) < period) {
    return UpdateDecision.notDue;
  }

  // A clock that has gone *backwards* — a manual change, a timezone rebase, a
  // restored backup carrying a future timestamp — makes the difference
  // negative, which is smaller than any period and reads as "not due" above.
  // That is the right answer and it is worth naming: it fails toward *not*
  // crawling every source the user has installed, which is the direction a
  // wrong answer should fail in.

  if (wifiOnly && !onWifi) return UpdateDecision.waitingForWifi;
  return UpdateDecision.run;
}
