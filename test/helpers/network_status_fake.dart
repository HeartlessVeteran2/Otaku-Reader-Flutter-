import 'package:otaku_reader/core/platform/network_status.dart';

/// A `NetworkStatus` with a fixed answer, recording how often it was asked.
///
/// The call *count* matters as much as the answer: `refreshIfDue` deliberately
/// does not query the platform until the schedule has already said yes, so a
/// test that only checked the decision would pass with that ordering reversed
/// — and the reversed version hits a platform channel on every app resume to
/// answer a question that usually ends in "not due".
class FakeNetworkStatus implements NetworkStatus {
  FakeNetworkStatus({this.unmetered = true});

  final bool unmetered;
  int asked = 0;

  @override
  Future<bool> isUnmetered() async {
    asked++;
    return unmetered;
  }
}
