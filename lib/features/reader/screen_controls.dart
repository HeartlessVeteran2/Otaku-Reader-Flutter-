import 'package:flutter/services.dart';

/// Which way up the reader is pinned.
///
/// Persisted by `index`, so this may only be appended to — the rule
/// `ReadingDirection` already carries, and the one `int status = 5` is in the
/// mistakes table for.
enum ReaderOrientation {
  /// Whatever the device is doing, including its own rotation lock.
  system,
  portrait,
  landscape;

  /// What to hand `SystemChrome.setPreferredOrientations`.
  ///
  /// An **empty list means "no preference"**, which is how Flutter spells
  /// "follow the device" — not a synonym for "portrait". Both halves of each
  /// axis are listed so a device held upside down still rotates; naming only
  /// `portraitUp` pins the reader against a user who is lying down, which is
  /// most of the reading this app is for.
  List<DeviceOrientation> get preferred => switch (this) {
    ReaderOrientation.system => const [],
    ReaderOrientation.portrait => const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ],
    ReaderOrientation.landscape => const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  };

  String get label => switch (this) {
    ReaderOrientation.system => 'Follow device',
    ReaderOrientation.portrait => 'Portrait',
    ReaderOrientation.landscape => 'Landscape',
  };
}

/// The platform calls a chapter makes about the screen itself.
///
/// A seam for the same reason [ScreenWakelock] is one, and the reason is
/// recorded in `CLAUDE.md` rather than being a matter of taste: two Settings
/// switches shipped here writing keys that nothing read, and **a round-trip
/// test is exactly what would have passed the whole time they were dead.** So
/// the thing a test has to be able to watch is the *request*, and a static
/// `SystemChrome` call is something a host-VM test can neither make nor
/// observe.
///
/// Every method returns a future that always completes. The reader fires them
/// unawaited from `onInit`/`onClose`, where a rejection becomes an unhandled
/// async error with nobody to catch it.
abstract class ReaderScreenControls {
  /// Pins the reader, or releases it with [ReaderOrientation.system].
  Future<void> setOrientation(ReaderOrientation orientation);

  /// Hides or restores the system bars.
  Future<void> setImmersive(bool on);

  /// Asks the platform to keep this window out of screenshots and recents.
  ///
  /// Returns **false when the platform did not apply it**, rather than
  /// swallowing that like the wakelock does. The two are not the same promise:
  /// a wakelock is a courtesy, and this one is the difference between a reader
  /// believing a screenshot is blocked and it not being. A setting that claims
  /// a privacy property it does not have is worse than no setting.
  Future<bool> setSecure(bool on);
}

/// The real one.
///
/// Orientation and immersive go through `SystemChrome`, which is plain Flutter
/// — no plugin and no channel of our own. Only the secure flag needs one,
/// because Android exposes `FLAG_SECURE` through `WindowManager` and Flutter
/// has no wrapper for it.
class PlatformReaderScreenControls implements ReaderScreenControls {
  const PlatformReaderScreenControls();

  static const _channel = MethodChannel('otaku_reader/screen');

  @override
  Future<void> setOrientation(ReaderOrientation orientation) async {
    try {
      await SystemChrome.setPreferredOrientations(orientation.preferred);
    } catch (_) {}
  }

  @override
  Future<void> setImmersive(bool on) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        // `edgeToEdge` rather than `manual` with every overlay listed: this app
        // draws under the bars everywhere else, and restoring to `manual` would
        // leave the reader's exit looking different from every other screen.
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (_) {}
  }

  @override
  Future<bool> setSecure(bool on) async {
    try {
      final applied = await _channel.invokeMethod<bool>('setSecure', on);
      return applied ?? false;
    } on MissingPluginException {
      // A platform with no implementation — the host VM under test, or a
      // desktop build. Reported as "not applied", which is true.
      return false;
    } catch (_) {
      return false;
    }
  }
}
