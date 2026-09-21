import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';

/// Everything the reader needs to resolve a tap, read from the KV tier.
///
/// A plain class rather than a controller: the reader holds one, the editor
/// holds one, and neither needs the other to exist. Ported from AnymeX's
/// `TapZoneRepository`, which is the same shape.
class TapZoneSettings {
  const TapZoneSettings._();

  /// Whether tapping does anything beyond showing the controls.
  ///
  /// Default **on**, as AnymeX's is. Off is not "no zones" — it is the
  /// behaviour this reader had before zones existed, where any tap toggles the
  /// chrome, so turning the feature off has to leave a working reader rather
  /// than a screen that ignores taps.
  static bool get enabled => ReaderKeys.tapZonesEnabled.get<bool>(true);

  static void setEnabled(bool value) =>
      ReaderKeys.tapZonesEnabled.set<bool>(value);

  /// Whether the bands mirror when the reading direction is reversed.
  ///
  /// Default **on**, and this is the correction AnymeX does not have. Taken
  /// from the Kotlin Otaku-Reader, whose `TapZoneConfig` carries
  /// `invertForRtl: Boolean = true` for exactly this. It stays a setting rather
  /// than becoming structural because the two preferences are both real: mirror
  /// with the text, or keep the zones where your thumb learned them.
  static bool get mirrorWhenReversed =>
      ReaderKeys.tapZonesMirrorReversed.get<bool>(true);

  static void setMirrorWhenReversed(bool value) =>
      ReaderKeys.tapZonesMirrorReversed.set<bool>(value);

  /// A short vibration when a zone fires.
  ///
  /// The Kotlin app carries `hapticFeedback: Boolean = true`; AnymeX has none.
  /// It earns its place because a tap zone is invisible: without it, the only
  /// feedback that a tap was understood is the page moving, and the one tap
  /// that moves nothing — the chrome zone, or a `none` band — is
  /// indistinguishable from a tap the app missed.
  static bool get haptics => ReaderKeys.tapZonesHaptics.get<bool>(true);

  static void setHaptics(bool value) =>
      ReaderKeys.tapZonesHaptics.set<bool>(value);

  static ReaderKeys _key(ReadingLayout layout) =>
      layout == ReadingLayout.webtoon
      ? ReaderKeys.tapZonesContinuous
      : ReaderKeys.tapZonesPaged;

  /// The profile [layout] reads, or the standard one when nothing valid is
  /// stored.
  ///
  /// Separate per layout for the same reason the directions are: a profile
  /// authored for a page turn is not the one you want down a long strip, and
  /// one stored value means editing either overwrites both.
  static TapZoneProfile profileFor(ReadingLayout layout) =>
      TapZoneProfile.decode(_key(layout).get<String?>()) ??
      TapZoneProfile.standard;

  // There is deliberately no writer here yet. The editor is the next slice and
  // it is what decides the write contract -- whether an invalid profile is
  // refused silently, reported, or cannot be produced at all -- so guessing
  // that now would ship an API with no caller to shape it. `profileFor` falls
  // back to the standard bands until then, which is exactly what the reader
  // gets today.
}
