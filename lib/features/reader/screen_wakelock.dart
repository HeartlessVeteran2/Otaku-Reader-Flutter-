import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the device screen awake while a chapter is open.
///
/// An interface rather than a bare `WakelockPlus` call, for the same reason
/// `AniListAuth` takes a `FlutterSecureStorage`: the plugin is a *static*
/// platform channel. A host-VM test cannot call it — it throws
/// `MissingPluginException` — and, more to the point, cannot observe it. The
/// setting this backs shipped as a live control with nothing behind it, so a
/// test that can watch the request being made is the whole point of the seam.
abstract class ScreenWakelock {
  Future<void> enable();
  Future<void> disable();
}

/// The real one.
///
/// Failures are swallowed on purpose. A wakelock is a courtesy: a platform that
/// refuses one must not stop a chapter opening, and there is no second thing to
/// try. This is also why both methods return a future that always completes —
/// the reader fires them unawaited from `onInit`/`onClose`, where a rejection
/// would become an unhandled async error with nobody to catch it.
class WakelockPlusScreen implements ScreenWakelock {
  const WakelockPlusScreen();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
