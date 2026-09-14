import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';

/// Whether adult sources and titles are shown, as **one reactive value**.
///
/// Every controller used to copy this out of the key/value tier in `onInit`,
/// which meant a write from Settings reached none of them: the setting flipped
/// the stored value and the live copies went on as before, so the home shelves
/// kept showing adult titles until the app restarted.
///
/// Browse only appeared to work because its own switch wrote *both* the key and
/// its own copy — a third call site would have had to remember to do the same.
/// One holder that everyone observes removes the class of bug instead of adding
/// another thing to keep in sync.
///
/// Deliberately not a `KvHelper` read at each use site: the filter runs inside
/// a build, and a synchronous database read per rebuild is a cost this pays
/// once at startup instead.
class NsfwPreference {
  NsfwPreference() {
    shown.value = SourceKeys.showNsfwSources.get<bool>(false);
  }

  /// Observe this rather than reading the key.
  final shown = false.obs;

  /// Writes the stored value and notifies every observer.
  ///
  /// A no-op when nothing changes, so a screen rebuilding its switch cannot
  /// trigger a shelf rebuild by writing the value it already had.
  ///
  /// **Storage first, then the observers.** The other order looks equivalent
  /// and is not: if the write throws, the app would be left showing one thing
  /// while the database remembered another, and the no-op guard above would
  /// make toggling back to the same value a silent nothing — so the user could
  /// never retry, and the setting would revert on the next launch with no
  /// indication why. Writing first means a failure leaves the value untouched
  /// and the retry still available.
  void setShown(bool value) {
    if (shown.value == value) return;
    SourceKeys.showNsfwSources.set<bool>(value);
    shown.value = value;
  }
}
