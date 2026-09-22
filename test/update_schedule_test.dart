import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/features/updates/scheduling/update_schedule.dart';

/// The auto-refresh policy.
///
/// A pure function with every input passed in, so this suite needs no clock,
/// no database, no network and no platform channel — which is the point of
/// the shape. The alternative (a controller reading keys and plugins itself)
/// is exactly how two Settings switches shipped here writing keys that nothing
/// read.
void main() {
  final now = DateTime.utc(2026, 9, 22, 12);

  UpdateDecision decide({
    UpdateInterval interval = UpdateInterval.daily,
    DateTime? lastCheck,
    bool wifiOnly = false,
    bool onWifi = true,
  }) => shouldRefreshLibrary(
    interval: interval,
    lastCheck: lastCheck,
    now: now,
    wifiOnly: wifiOnly,
    onWifi: onWifi,
  );

  test('manual never runs on its own', () {
    // Not "the feature is off" — the Updates tab's pull-to-refresh is
    // untouched. This is "do not crawl my sources without me".
    expect(
      decide(interval: UpdateInterval.manual, lastCheck: null),
      UpdateDecision.disabled,
    );
  });

  test('a library never refreshed is due', () {
    expect(decide(lastCheck: null), UpdateDecision.run);
  });

  test('inside the period it is not due; past it, it runs', () {
    expect(
      decide(lastCheck: now.subtract(const Duration(hours: 23, minutes: 59))),
      UpdateDecision.notDue,
    );
    expect(
      decide(lastCheck: now.subtract(const Duration(hours: 24, minutes: 1))),
      UpdateDecision.run,
    );
  });

  test('the boundary itself runs', () {
    // `<` not `<=`: exactly one period elapsed is due. A daily refresh that
    // needs 24 hours *and a minute* drifts a minute later every day, which is
    // the kind of thing nobody notices for a month.
    expect(
      decide(lastCheck: now.subtract(const Duration(hours: 24))),
      UpdateDecision.run,
    );
  });

  test('each interval measures its own period', () {
    for (final interval in UpdateInterval.values) {
      final period = interval.period;
      if (period == null) continue;
      expect(
        decide(interval: interval, lastCheck: now.subtract(period * 0.5)),
        UpdateDecision.notDue,
        reason: '${interval.name} at half its period',
      );
      expect(
        decide(interval: interval, lastCheck: now.subtract(period * 1.5)),
        UpdateDecision.run,
        reason: '${interval.name} at 1.5x its period',
      );
    }
  });

  group('Wi-Fi only', () {
    test('holds off on mobile data, and says so', () {
      // Its own answer, not `notDue`. "Waiting for Wi-Fi" is something the
      // user can act on; collapsing it into "not due" makes a working feature
      // indistinguishable from a broken one.
      expect(
        decide(lastCheck: null, wifiOnly: true, onWifi: false),
        UpdateDecision.waitingForWifi,
      );
    });

    test('runs on Wi-Fi', () {
      expect(
        decide(lastCheck: null, wifiOnly: true, onWifi: true),
        UpdateDecision.run,
      );
    });

    test('is ignored when the switch is off', () {
      expect(
        decide(lastCheck: null, wifiOnly: false, onWifi: false),
        UpdateDecision.run,
      );
    });

    test('a not-due schedule is not reported as waiting for Wi-Fi', () {
      // The order of the two checks. Reporting the network first would put a
      // "waiting for Wi-Fi" banner on screen for a refresh that was not due
      // for another twenty hours.
      expect(
        decide(
          lastCheck: now.subtract(const Duration(hours: 4)),
          wifiOnly: true,
          onWifi: false,
        ),
        UpdateDecision.notDue,
      );
    });
  });

  test('a clock that went backwards does not trigger a crawl', () {
    // A restored backup or a manual clock change can leave a timestamp in the
    // future. The difference is then negative, which reads as "not due" — and
    // that is the direction a wrong answer should fail in, because the other
    // one is one request per installed source.
    expect(
      decide(lastCheck: now.add(const Duration(days: 3))),
      UpdateDecision.notDue,
    );
  });
}
