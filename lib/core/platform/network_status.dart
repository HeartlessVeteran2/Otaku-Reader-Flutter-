import 'package:connectivity_plus/connectivity_plus.dart';

/// What kind of connection the device is on.
///
/// A seam for the same reason `ScreenWakelock` and `ReaderScreenControls` are
/// ones: the plugin is a platform channel, so a host-VM test can neither call
/// it nor observe it — and the setting behind this is a *switch*, which is
/// precisely the shape that has shipped here twice writing a key nothing read.
/// The decision that uses this (`shouldRefreshLibrary`) takes a plain `bool`,
/// so the policy is testable with no platform at all and this only has to
/// answer one question honestly.
abstract class NetworkStatus {
  /// Whether the connection is one a library-wide refresh should be run over.
  ///
  /// "Unmetered" rather than "Wi-Fi", because the honest question is *does
  /// this cost the user money*, and Wi-Fi is the common answer rather than the
  /// only one — ethernet on a desktop build is equally free.
  Future<bool> isUnmetered();

  /// Fires when the connection may have changed, so a held queue can start.
  ///
  /// The library refresh does not need this — it is asked on launch and on
  /// resume, and those are the only moments it runs. The **download queue**
  /// does: a queue held back for Wi-Fi re-pumps when something finishes, and
  /// when everything is held nothing ever finishes, so without a nudge from
  /// outside it waits forever. Joining Wi-Fi and watching the queue stay
  /// still reads as the app being broken, and "background the app and come
  /// back" is not a fix a user can be expected to discover.
  ///
  /// Deliberately `void` rather than carrying the new state. A consumer that
  /// needs the answer asks [isUnmetered], which is the one method allowed to
  /// be wrong about the platform; an event that carried a value would give
  /// two sources for one fact, and this file's own history is that a value
  /// and its meaning drift apart when they arrive separately.
  Stream<void> get onChanged;
}

/// The real one.
///
/// **A failure answers `true`, and that is the deliberate direction.** The
/// alternative — treating "I could not tell" as metered — permanently stops
/// automatic refreshes on any device where the plugin misbehaves, and the
/// symptom is a feature that silently never runs, which is the hardest kind
/// of bug to notice. Answering `true` costs at worst one refresh the user did
/// not want on mobile data, which is visible and recoverable: they can turn
/// the interval down or the switch off.
class ConnectivityNetworkStatus implements NetworkStatus {
  const ConnectivityNetworkStatus();

  @override
  Stream<void> get onChanged => Connectivity().onConnectivityChanged;

  @override
  Future<bool> isUnmetered() async {
    try {
      final results = await Connectivity().checkConnectivity();
      // `checkConnectivity` returns a **list** — a device can be on Wi-Fi and
      // VPN at once, and reading `.first` would let the VPN entry decide. Any
      // unmetered member is enough.
      // **`vpn` is deliberately not in this set**, though it was at first.
      // A VPN is a tunnel, not a link: it runs over whatever is underneath,
      // and over mobile data it is exactly the case this guard exists to
      // stop. When the tunnel runs over Wi-Fi the list carries `wifi` as
      // well, so that case is already covered by the member below — which
      // means including `vpn` could only ever turn a *metered* connection
      // into a false yes. Found by `codeant-ai`.
      return results.any(
        (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
      );
    } catch (_) {
      return true;
    }
  }
}
