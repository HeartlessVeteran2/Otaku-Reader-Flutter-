import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/screens/accounts_screen.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';

/// How a multiplier is written on its row: `1.0x`, `0.25x`, `2.5x`.
///
/// `1.0x` rather than `100%` because the sliders are multipliers, and a
/// percentage reads as "how much of the maximum" instead of "how many times
/// the default".
///
/// Two decimals, trimmed to one when the second is a zero. It was
/// `toStringAsFixed(1)`, which **lied about six of the roundness slider's
/// thirteen stops**: that slider steps by 3.0 / 12 = 0.25, so a reader sitting
/// on 0.25 saw "0.3x" and one on 2.75 saw "2.8x" — a row reporting a number
/// the app is not set to. Found by `codeant-ai` on #54.
///
/// Fixed in the formatter rather than by widening the step, because the
/// formatter is what was wrong: one that cannot express its own slider's stops
/// is a bug whichever step it is handed, and the next person to change
/// `divisions` should not have to remember this.
///
/// Top-level and public for the test, which walks **every stop of every
/// slider** and parses the label back — the only shape that catches a step
/// the formatter cannot say. A test pinned to the one value on screen would
/// have passed throughout.
String scaleLabel(double value) {
  final two = value.toStringAsFixed(2);
  return '${two.endsWith('0') ? two.substring(0, two.length - 1) : two}x';
}

/// Appearance, reader defaults and source behaviour.
///
/// Every control here writes through immediately. There is no Save button, so
/// there is no state to lose and nothing to reconcile if the app is killed
/// mid-change.
///
/// **Flat, not a hub.** AnymeX's `settings.dart` is 13 category tiles pushing
/// to sub-screens, because its settings are ~12,000 lines across 19 screens.
/// This is twelve controls, where a hub is an extra tap for nothing. The
/// trigger for changing that is written down rather than left to taste: when
/// backup, storage, logs and tap zones land, each wants a screen, and at that
/// point AnymeX's hub — and its searchable registry — is simply correct.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThemeController get _theme => Get.find<ThemeController>();

  /// Reader defaults live in the key/value tier rather than in a controller:
  /// the reader reads them at open time, and there may be no reader alive.
  int _readerInt(ReaderKeys key, int fallback) => key.get<int>(fallback);
  bool _readerBool(ReaderKeys key, bool fallback) => key.get<bool>(fallback);

  void _setInt(ReaderKeys key, int value) {
    key.set<int>(value);
    setState(() {});
  }

  void _setBool(ReaderKeys key, bool value) {
    key.set<bool>(value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold.slivers(
      title: 'Settings',
      slivers: [
        SliverChromeSection(
          label: 'Appearance',
          children: [
            Obx(
              () => ChromeTile.choice(
                icon: Iconsax.moon,
                title: 'Theme',
                subtitle: 'Which palette the app draws in',
                labels: const ['System', 'Light', 'Dark'],
                selectedIndex: ThemeMode.values.indexOf(_theme.themeMode.value),
                onSelected: (i) => _theme.setThemeMode(ThemeMode.values[i]),
              ),
            ),
            Obx(
              () => ChromeTile.toggle(
                icon: Iconsax.mobile,
                title: 'Pure black dark theme',
                subtitle: 'Saves power on OLED screens',
                value: _theme.isOled.value,
                onChanged: _theme.setOled,
              ),
            ),
            Obx(
              () => ChromeTile.choice(
                icon: Iconsax.colorfilter,
                title: 'Colour source',
                subtitle: 'Material You takes the palette from the wallpaper',
                labels: const ['Default', 'Material You', 'Custom'],
                selectedIndex: ThemeSource.values.indexOf(_theme.source.value),
                onSelected: (i) => _theme.setSource(ThemeSource.values[i]),
              ),
            ),
            Obx(
              () => ChromeTile.toggle(
                icon: Iconsax.brush_2,
                title: 'Tint from the cover',
                subtitle: 'The manga you have open colours the app',
                value: _theme.useCoverColor.value,
                onChanged: _theme.setUseCoverColor,
              ),
            ),
          ],
        ),
        SliverChromeSection(
          label: 'Shape',
          children: [
            // AnymeX's UI multipliers, and its own slider bounds so a value
            // that works there works here. Every one of them reaches zero on
            // purpose: square corners, no glow and no blur are real choices,
            // and the last is the one that costs the least to draw.
            Obx(
              () => ChromeTile.slider(
                icon: Iconsax.frame,
                title: 'Corner roundness',
                subtitle: 'Scales every rounded corner in the app',
                value: _theme.radiusScale.value,
                min: ChromeMetrics.minScale,
                max: ChromeMetrics.maxRadiusScale,
                divisions: 12,
                valueLabel: scaleLabel(_theme.radiusScale.value),
                onChanged: _theme.setRadiusScale,
              ),
            ),
            Obx(
              () => ChromeTile.slider(
                icon: Iconsax.flash,
                title: 'Glow',
                subtitle: 'How far a shadow spreads behind its surface',
                value: _theme.glowScale.value,
                min: ChromeMetrics.minScale,
                max: ChromeMetrics.maxGlowScale,
                divisions: 10,
                valueLabel: scaleLabel(_theme.glowScale.value),
                onChanged: _theme.setGlowScale,
              ),
            ),
            Obx(
              () => ChromeTile.slider(
                icon: Iconsax.blur,
                title: 'Header blur',
                subtitle: 'The frosted pills, and how soft every shadow is',
                value: _theme.blurScale.value,
                min: ChromeMetrics.minScale,
                max: ChromeMetrics.maxBlurScale,
                divisions: 10,
                valueLabel: scaleLabel(_theme.blurScale.value),
                onChanged: _theme.setBlurScale,
              ),
            ),
          ],
        ),
        SliverChromeSection(
          label: 'Reader defaults',
          children: [
            // A default, not an override: a manga already opened keeps
            // whatever it was last read with, because that choice was made
            // per series.
            ChromeTile.choice(
              icon: Iconsax.book_1,
              title: 'Reading layout',
              subtitle: 'Webtoon scrolls continuously; paged turns a page',
              labels: const ['Paged', 'Webtoon'],
              selectedIndex: _readerInt(
                ReaderKeys.readingLayout,
                0,
              ).clamp(0, ReadingLayout.values.length - 1),
              onSelected: (i) => _setInt(ReaderKeys.readingLayout, i),
            ),
            ChromeTile.choice(
              icon: Iconsax.arrow_swap_horizontal,
              title: 'Reading direction',
              subtitle: 'Most manga reads right to left',
              labels: const ['Left to right', 'Right to left'],
              selectedIndex: _readerInt(
                ReaderKeys.readingDirection,
                0,
              ).clamp(0, ReadingDirection.values.length - 1),
              onSelected: (i) => _setInt(ReaderKeys.readingDirection, i),
            ),
            // Taken when the reader opens and released when it closes, so the
            // switch only decides what the *next* chapter does.
            ChromeTile.toggle(
              icon: Iconsax.sun_1,
              title: 'Keep the screen on',
              subtitle: 'While a chapter is open',
              value: _readerBool(
                ReaderKeys.keepScreenOn,
                ReaderDefaults.keepScreenOn,
              ),
              onChanged: (v) => _setBool(ReaderKeys.keepScreenOn, v),
            ),
            // Defaults to off, as AnymeX's does. The reader's own controls
            // already carry the number one tap away, so a pill floating over
            // the artwork is worth asking for rather than turning off.
            ChromeTile.toggle(
              icon: Iconsax.document,
              title: 'Show the page number',
              subtitle: 'Stays on screen with the controls hidden',
              value: _readerBool(
                ReaderKeys.showPageIndicator,
                ReaderDefaults.showPageIndicator,
              ),
              onChanged: (v) => _setBool(ReaderKeys.showPageIndicator, v),
            ),
          ],
        ),
        SliverChromeSection(
          label: 'Sources',
          children: [
            Obx(
              // Reads and writes the shared holder, not the key directly.
              // Writing the key alone flipped the stored value while the live
              // Home and Browse controllers carried on with their own copies,
              // so the setting appeared to do nothing until a restart.
              () => ChromeTile.toggle(
                icon: Iconsax.eye_slash,
                title: 'Show 18+ sources',
                subtitle: 'Also hides adult titles from the home page',
                value: Get.find<NsfwPreference>().shown.value,
                onChanged: Get.find<NsfwPreference>().setShown,
              ),
            ),
            const ChromeTile(
              icon: Iconsax.info_circle,
              title: 'Extensions and repositories',
              subtitle: 'Manage these from the Browse tab',
              enabled: false,
              showChevron: false,
            ),
          ],
        ),
        SliverChromeSection(
          label: 'Accounts',
          children: [
            Obx(() {
              final auth = Get.find<AniListAuth>();
              final viewer = auth.viewer.value;
              return ChromeTile(
                icon: Iconsax.user_octagon,
                title: 'AniList',
                // Four states, not two, and `isReady` is the one that is
                // easy to miss. `AppBindings` launches `restore()` unawaited,
                // so at startup there is a real interval where the token has
                // not been read yet — and rendering "Not signed in" there
                // tells a signed-in user the opposite of the truth for as
                // long as the keystore takes. Telling those two apart is the
                // entire reason `isReady` exists; the Accounts screen this
                // row opens honours it, and this row did not.
                //
                // `isConfigured` is checked first because it is known without
                // reading anything: a build with no client id has nothing to
                // be ready for.
                subtitle: !auth.isConfigured
                    ? 'Not set up in this build'
                    : !auth.isReady.value
                    ? 'Checking…'
                    : viewer == null
                    ? 'Not signed in'
                    : 'Signed in as ${viewer.name}',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountsScreen(),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }
}
