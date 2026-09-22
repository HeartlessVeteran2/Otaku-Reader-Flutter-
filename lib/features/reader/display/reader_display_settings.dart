import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/features/reader/display/reader_display.dart';

/// How the reader tints, dims and desaturates a page, read from the KV tier.
///
/// The same shape as `TapZoneSettings`, and for the same reason: the reader
/// reads these and the Settings rows render them, so a default declared at
/// either call site is how a switch comes to show the opposite of what the
/// reader does with every file staying self-consistent.
///
/// **These keys all existed already, and nothing read them.** They were declared
/// in `keys.dart` from the start, which is exactly the state `FEATURES.md` was
/// rebuilt to catch — a checklist that counts declared keys reports parity for
/// a feature nobody built.
///
/// The count is deliberately not restated here. `FEATURES.md` carries it once,
/// derived from the enum by `features_doc_test.dart`; a number repeated in a
/// doc comment is a number that drifts, which is the defect this very slice
/// shipped and then had pointed out twice.
class ReaderDisplaySettings {
  const ReaderDisplaySettings._();

  /// How far the page is dimmed, as a percentage, `0` to [maxDim].
  ///
  /// **Dim, not brightness**, and the name is the honest one. AnymeX calls this
  /// brightness and its slider runs 0 to −75, painting black at
  /// `abs(value)/100` opacity — it can only ever darken. Raising the screen
  /// past its system setting needs the platform's own brightness control and a
  /// plugin this app does not carry, so a control labelled Brightness that
  /// cannot brighten would be a third dead switch in this reader's history.
  ///
  /// Stored as a positive magnitude rather than AnymeX's negative one. Its sign
  /// is vestigial — nothing reads a positive value — and a stored `-40` invites
  /// a future reader to wonder what `+40` does.
  static const maxDim = 75;

  static int get dim =>
      ReaderKeys.customBrightnessValue.get<int>(0).clamp(0, maxDim);

  static void setDim(int value) =>
      ReaderKeys.customBrightnessValue.set<int>(value.clamp(0, maxDim));

  /// Whether the dim is applied at all, kept apart from its magnitude.
  ///
  /// Two keys rather than "zero means off", because a reader who dims to 40,
  /// turns it off and turns it back on wants 40 again rather than 0. Collapsing
  /// them loses the setting every time it is toggled.
  static bool get dimEnabled =>
      ReaderKeys.customBrightnessEnabled.get<bool>(false);

  static void setDimEnabled(bool value) =>
      ReaderKeys.customBrightnessEnabled.set<bool>(value);

  static bool get filterEnabled =>
      ReaderKeys.colorFilterEnabled.get<bool>(false);

  static void setFilterEnabled(bool value) =>
      ReaderKeys.colorFilterEnabled.set<bool>(value);

  /// The filter colour as a packed ARGB int.
  ///
  /// Default is a warm amber at 25% alpha — a sepia-ish night filter, which is
  /// what this control is reached for. Zero would be a fully transparent black
  /// and would make the switch look broken on first use.
  static int get filterColor =>
      ReaderKeys.colorFilterValue.get<int>(0x40FFB000);

  static void setFilterColor(int value) =>
      ReaderKeys.colorFilterValue.set<int>(value);

  static ReaderBlend get filterBlend =>
      ReaderBlend.fromIndex(ReaderKeys.colorFilterMode.get<int>(0));

  static void setFilterBlend(ReaderBlend value) =>
      ReaderKeys.colorFilterMode.set<int>(value.index);

  static bool get greyscale => ReaderKeys.grayscaleEnabled.get<bool>(false);

  static void setGreyscale(bool value) =>
      ReaderKeys.grayscaleEnabled.set<bool>(value);

  static bool get invert => ReaderKeys.invertColorsEnabled.get<bool>(false);

  static void setInvert(bool value) =>
      ReaderKeys.invertColorsEnabled.set<bool>(value);

  /// The page's backdrop.
  ///
  /// Clamped through `values.length`, never a literal — the `int status = 5`
  /// row of the mistakes table, and the clamp that was wrong in
  /// `ReaderController.onInit` until an enum gained a member.
  static ReaderBackground get background =>
      ReaderBackground.values[ReaderKeys.readerTheme
          .get<int>(ReaderBackground.black.index)
          .clamp(0, ReaderBackground.values.length - 1)];

  static void setBackground(ReaderBackground value) =>
      ReaderKeys.readerTheme.set<int>(value.index);
}
