import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/theme/brand.dart';

/// How the seed colour is chosen.
enum ThemeSource {
  /// A fixed app seed.
  standard,

  /// Material You — the platform's own palette.
  dynamicColor,

  /// A palette entry or a user-entered hex.
  custom,
}

/// The M3 tonal algorithms, exposed as a user setting because they change the
/// feel of the whole app far more than the seed colour does.
const kSchemeVariants = DynamicSchemeVariant.values;

class ThemeController extends GetxController {
  /// The app's own seed, and the starting point for a custom colour.
  static const _defaultSeed = BrandPalette.petal;

  final source = ThemeSource.standard.obs;
  final themeMode = ThemeMode.system.obs;
  final isOled = false.obs;
  final variantIndex = 0.obs;
  final customColor = _defaultSeed.obs;

  /// Set by the details screen from a cover's dominant colour when
  /// `useCoverColor` is on. Null restores the configured seed.
  final coverSeed = Rxn<Color>();
  final useCoverColor = false.obs;

  /// AnymeX's UI multipliers. See `ChromeMetrics` for why they ride the theme
  /// rather than being resolved through `Get.find` at every call site.
  final radiusScale = ChromeMetrics.standard.radiusScale.obs;
  final glowScale = ChromeMetrics.standard.glowScale.obs;
  final blurScale = ChromeMetrics.standard.blurScale.obs;

  Color? _platformSeed;

  @override
  void onInit() {
    super.onInit();
    source.value = ThemeSource
        .values[ThemeKeys.themeMode.get<int>(ThemeSource.standard.index)];
    themeMode.value = ThemeMode
        .values[ThemeKeys.isSystemMode.get<int>(ThemeMode.system.index)];
    isOled.value = ThemeKeys.isOled.get<bool>(false);
    variantIndex.value = ThemeKeys.selectedVariantIndex
        .get<int>(kDefaultSchemeVariant.index)
        .clamp(0, kSchemeVariants.length - 1);
    final hex = ThemeKeys.customHexColor.get<int>(_defaultSeed.toARGB32());
    customColor.value = Color(hex);
    useCoverColor.value = ThemeKeys.useCoverColor.get<bool>(false);
    // Clamped on the way in as well as on the way out. A value that came from
    // a backup, a hand-edited row or an older build with different bounds is
    // not the user's choice, and an unclamped 40x radius is an app nobody can
    // read.
    radiusScale.value = _clampScale(
      ThemeKeys.radiusScale.get<double>(ChromeMetrics.standard.radiusScale),
      ChromeMetrics.maxRadiusScale,
    );
    glowScale.value = _clampScale(
      ThemeKeys.glowScale.get<double>(ChromeMetrics.standard.glowScale),
      ChromeMetrics.maxGlowScale,
    );
    blurScale.value = _clampScale(
      ThemeKeys.blurScale.get<double>(ChromeMetrics.standard.blurScale),
      ChromeMetrics.maxBlurScale,
    );
    if (source.value == ThemeSource.dynamicColor) loadPlatformPalette();
  }

  Future<void> loadPlatformPalette() async {
    final palette = await DynamicColorPlugin.getCorePalette();
    // A device with no Material You support returns null; falling back to the
    // configured seed keeps the setting selectable rather than broken.
    _platformSeed = palette == null ? null : Color(palette.primary.get(40));
    update();
    refreshTheme();
  }

  void setSource(ThemeSource value) {
    source.value = value;
    ThemeKeys.themeMode.set<int>(value.index);
    if (value == ThemeSource.dynamicColor && _platformSeed == null) {
      loadPlatformPalette();
    } else {
      refreshTheme();
    }
  }

  void setThemeMode(ThemeMode value) {
    themeMode.value = value;
    ThemeKeys.isSystemMode.set<int>(value.index);
    refreshTheme();
  }

  void setOled(bool value) {
    isOled.value = value;
    ThemeKeys.isOled.set<bool>(value);
    refreshTheme();
  }

  void setVariant(int index) {
    variantIndex.value = index.clamp(0, kSchemeVariants.length - 1);
    ThemeKeys.selectedVariantIndex.set<int>(variantIndex.value);
    refreshTheme();
  }

  void setCustomColor(Color value) {
    customColor.value = value;
    ThemeKeys.customHexColor.set<int>(value.toARGB32());
    refreshTheme();
  }

  void setUseCoverColor(bool value) {
    useCoverColor.value = value;
    ThemeKeys.useCoverColor.set<bool>(value);
    if (!value) coverSeed.value = null;
    refreshTheme();
  }

  void applyCoverSeed(Color? colour) {
    if (!useCoverColor.value) return;
    coverSeed.value = colour;
    refreshTheme();
  }

  /// The seed in force, and whether it is the app's own.
  ///
  /// The two travel together because they are one decision. The mark's navy and
  /// coral fill the secondary and tertiary families **only** when the brand seed
  /// is what is being used: a user who picks green, or a cover that comes back
  /// green, asked for green — handing them green with the logo's navy and coral
  /// stapled on is not their colour, it is ours wearing theirs.
  ({Color seed, bool isBrand}) get _resolvedSeed {
    if (useCoverColor.value && coverSeed.value != null) {
      return (seed: coverSeed.value!, isBrand: false);
    }
    return switch (source.value) {
      ThemeSource.standard => (seed: _defaultSeed, isBrand: true),
      // A device with no Material You support falls back to the app seed, and
      // that fallback *is* the brand palette — same seed, same three inks.
      ThemeSource.dynamicColor =>
        _platformSeed == null
            ? (seed: _defaultSeed, isBrand: true)
            : (seed: _platformSeed!, isBrand: false),
      ThemeSource.custom => (seed: customColor.value, isBrand: false),
    };
  }

  Color get seedColor => _resolvedSeed.seed;

  /// True when the whole mark's palette is in force, not just its pink.
  bool get usesBrandPalette => _resolvedSeed.isBrand;

  ThemeData theme(Brightness brightness) {
    final resolved = _resolvedSeed;
    final variant = kSchemeVariants[variantIndex.value];
    final scheme = resolved.isBrand
        ? brandColorScheme(brightness: brightness, variant: variant)
        : ColorScheme.fromSeed(
            seedColor: resolved.seed,
            brightness: brightness,
            dynamicSchemeVariant: variant,
          );
    final oled = isOled.value && brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: oled
          ? scheme.copyWith(
              surface: Colors.black,
              surfaceContainerLowest: Colors.black,
            )
          : scheme,
      scaffoldBackgroundColor: oled ? Colors.black : scheme.surface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      // Read through `context.radius` / `.glow` / `.blur`, so every chrome
      // widget picks the multipliers up from the theme it is already under
      // and a bare `MaterialApp` in a test gets `ChromeMetrics.standard`.
      extensions: [
        ChromeMetrics(
          radiusScale: radiusScale.value,
          glowScale: glowScale.value,
          blurScale: blurScale.value,
        ),
      ],
    );
  }

  /// Brings a multiplier inside the slider's own bounds.
  ///
  /// There is deliberately **no `isNaN` guard**, which is the check that
  /// suggests itself. Two measured facts remove the need for one, and both
  /// contradict the reasoning that would put it back:
  ///
  /// - **A non-finite value cannot come from disk.** The KV tier stores
  ///   `jsonEncode({'val': ...})`, and `dart:convert` refuses NaN and both
  ///   infinities outright — so there is no row to read back.
  /// - **`clamp` does not preserve NaN.** It compares through `compareTo`,
  ///   whose total order sorts NaN *above* every other double, so a NaN input
  ///   returns `max` rather than NaN. Measured on Dart 3.13.3:
  ///   `double.nan.clamp(0.0, 3.0) == 3.0`.
  ///
  /// So every input leaves here finite and inside `[minScale, max]`, which is
  /// the property the callers actually need and the one the test asserts.
  static double _clampScale(double value, double max) =>
      value.clamp(ChromeMetrics.minScale, max);

  void setRadiusScale(double value) {
    radiusScale.value = _clampScale(value, ChromeMetrics.maxRadiusScale);
    ThemeKeys.radiusScale.set<double>(radiusScale.value);
  }

  void setGlowScale(double value) {
    glowScale.value = _clampScale(value, ChromeMetrics.maxGlowScale);
    ThemeKeys.glowScale.set<double>(glowScale.value);
  }

  void setBlurScale(double value) {
    blurScale.value = _clampScale(value, ChromeMetrics.maxBlurScale);
    ThemeKeys.blurScale.set<double>(blurScale.value);
  }

  /// GetX rebuilds `GetMaterialApp` from `Get.changeTheme`, but the app reads
  /// both themes off this controller through `Obx`, so a plain `update()` on the
  /// reactive fields is all that is needed.
  void refreshTheme() => update();
}
