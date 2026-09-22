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
  Future<bool> isUnmetered() async {
    try {
      final results = await Connectivity().checkConnectivity();
      // `checkConnectivity` returns a **list** — a device can be on Wi-Fi and
      // VPN at once, and reading `.first` would let the VPN entry decide. Any
      // unmetered member is enough.
      return results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.ethernet ||
            r == ConnectivityResult.vpn,
      );
    } catch (_) {
      return true;
    }
  }
}
