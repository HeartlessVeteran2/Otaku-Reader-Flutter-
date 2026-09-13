import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';

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
  static const _defaultSeed = Color(0xFF6750A4);

  final source = ThemeSource.standard.obs;
  final themeMode = ThemeMode.system.obs;
  final isOled = false.obs;
  final variantIndex = 0.obs;
  final customColor = _defaultSeed.obs;

  /// Set by the details screen from a cover's dominant colour when
  /// `useCoverColor` is on. Null restores the configured seed.
  final coverSeed = Rxn<Color>();
  final useCoverColor = false.obs;

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
        .get<int>(0)
        .clamp(0, kSchemeVariants.length - 1);
    final hex = ThemeKeys.customHexColor.get<int>(_defaultSeed.toARGB32());
    customColor.value = Color(hex);
    useCoverColor.value = ThemeKeys.useCoverColor.get<bool>(false);
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

  Color get seedColor {
    if (useCoverColor.value && coverSeed.value != null) return coverSeed.value!;
    return switch (source.value) {
      ThemeSource.standard => _defaultSeed,
      ThemeSource.dynamicColor => _platformSeed ?? _defaultSeed,
      ThemeSource.custom => customColor.value,
    };
  }

  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: kSchemeVariants[variantIndex.value],
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
    );
  }

  /// GetX rebuilds `GetMaterialApp` from `Get.changeTheme`, but the app reads
  /// both themes off this controller through `Obx`, so a plain `update()` on the
  /// reactive fields is all that is needed.
  void refreshTheme() => update();
}
