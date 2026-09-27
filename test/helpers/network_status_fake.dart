import 'dart:async';

import 'package:otaku_reader/core/platform/network_status.dart';

/// A scriptable `NetworkStatus` that records how often it was asked.
///
/// The call *count* matters as much as the answer: `refreshIfDue` deliberately
/// does not query the platform until the schedule has already said yes, so a
/// test that only checked the decision would pass with that ordering reversed
/// — and the reversed version hits a platform channel on every app resume to
/// answer a question that usually ends in "not due".
class FakeNetworkStatus implements NetworkStatus {
  FakeNetworkStatus({this.unmetered = true});

  /// Mutable, because the download queue's whole Wi-Fi behaviour is about the
  /// answer *changing*: a held queue has to start when Wi-Fi arrives, and a
  /// fixed answer cannot produce the only state that matters.
  bool unmetered;
  int asked = 0;

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get onChanged => _changes.stream;

  /// Sets the answer and fires the event, in that order.
  ///
  /// The order is the point rather than convenience: a listener that calls
  /// `isUnmetered` on the event must see the new answer, which is exactly how
  /// the platform behaves and is the sequence the queue depends on.
  void change({required bool unmetered}) {
    this.unmetered = unmetered;
    _changes.add(null);
  }

  void close() => _changes.close();

  /// Event-loop turns each successive `isUnmetered()` waits before answering,
  /// consumed one per call.
  ///
  /// Exists so a test can make two reads complete **out of order**, which is
  /// the only state the generation guard is about. Without it the fake answers
  /// in the same turn it was asked, so two overlapping reads always finish in
  /// the order they started and the guard is unfalsifiable — measured: the
  /// out-of-order test passed with the guard deleted until this was added.
  final List<int> answerDelays = [];

  @override
  Future<bool> isUnmetered() async {
    asked++;
    // Captured **before** the delay, because the answer describes the moment
    // the platform was asked. Reading the field afterwards would make every
    // in-flight call report the newest value, which is precisely the staleness
    // under test.
    final answer = unmetered;
    final turns = answerDelays.isEmpty ? 0 : answerDelays.removeAt(0);
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return answer;
  }
}
