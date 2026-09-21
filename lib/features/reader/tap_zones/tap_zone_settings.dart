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
  /// Read as `Object?` and type-checked here, **not** as `String?`.
  ///
  /// `KvHelper.get` ends in `return val as T`, and its two re-widening guards
  /// match `T == double` and `T == int` only — so a row holding a number
  /// reached that cast as `String?` and threw a `TypeError` *before* [decode]
  /// was ever called. Every bit of care in the decoder sat behind a read that
  /// could not survive the row. Found by `sourcery-ai`, and reproduced: `type
  /// 'int' is not a subtype of type 'String?' in type cast`.
  ///
  /// Fixed here rather than in `KvHelper`, deliberately. The hazard is general
  /// — every `get<String?>` in the app shares it — but that primitive is read
  /// by every feature, and widening this PR to change it is how a reader
  /// change becomes a persistence change. Worth its own slice.
  static TapZoneProfile profileFor(ReadingLayout layout) {
    final stored = _key(layout).get<Object?>();
    return TapZoneProfile.decode(stored is String ? stored : null) ??
        TapZoneProfile.standard;
  }

  /// Stores [profile] as [layout]'s bands, and answers whether it did.
  ///
  /// The open question the previous slice left here was *whether an invalid
  /// profile is refused silently, reported, or cannot be produced at all*, and
  /// the editor answers **all three at once**: it edits the *cut points*
  /// between bands rather than the bands themselves, so the fractions sum to 1
  /// by construction and it cannot reach this method with an invalid profile.
  ///
  /// Measured rather than argued, because the construction rests on floating
  /// point: over every pair of cut points on the editor's 0.05 grid, 169 of 171
  /// sum to **exactly** 1.0 and the worst error is 1.1e-16 — thirteen orders of
  /// magnitude inside [TapZoneProfile.tolerance].
  ///
  /// The check still runs, and still reports, because this is a public writer
  /// and the next caller is a restore or an imported profile — neither of which
  /// is constructed here. A refusal deliberately leaves the stored row
  /// **alone**: clearing it would turn one bad write into the loss of bands the
  /// user had already authored, and nothing in the return value could tell the
  /// caller that had happened.
  static bool setProfileFor(ReadingLayout layout, TapZoneProfile profile) {
    if (!profile.isValid) return false;
    _key(layout).set<String>(profile.encode());
    return true;
  }

  /// Forgets [layout]'s stored bands, so [profileFor] answers
  /// [TapZoneProfile.standard] again.
  ///
  /// Deletes the row rather than writing the standard profile into it. The two
  /// are indistinguishable today and stop being so the moment the standard
  /// bands change: a user who never edited theirs should get the new default,
  /// and one who reset theirs asked for the default rather than for a copy of
  /// whatever it was on the day they tapped.
  static void resetProfileFor(ReadingLayout layout) => _key(layout).delete();
}
