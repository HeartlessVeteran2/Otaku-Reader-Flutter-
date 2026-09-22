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
import 'package:otaku_reader/features/library/screens/categories_screen.dart';
import 'package:otaku_reader/features/reader/screen_controls.dart';
import 'package:otaku_reader/features/settings/screens/accounts_screen.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/display/colour_filter_screen.dart';
import 'package:otaku_reader/features/reader/display/reader_display.dart';
import 'package:otaku_reader/features/reader/display/reader_display_settings.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_editor_screen.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';

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
            // Two rows, because the two layouts do not share a direction:
            // one value would mean a reader coming back from a right-to-left
            // manga found their next webtoon scrolling sideways. AnymeX keeps
            // one and force-overrides it whenever its webtoon detector fires,
            // which is the same admission by another route.
            //
            // The labels come off the enum, so a member added later cannot be
            // named here and left blank in the reader's own tooltip. Short
            // forms, because four full labels in one segmented row are stubs
            // at a doubled system font — and a `FittedBox` is not the fix, per
            // `CLAUDE.md`.
            ChromeTile.choice(
              icon: Iconsax.arrow_swap_horizontal,
              title: 'Paged direction',
              subtitle: 'Most manga reads right to left',
              labels: [for (final d in ReadingDirection.values) d.shortLabel],
              selectedIndex: _readerInt(
                ReaderKeys.readingDirection,
                ReadingDirection.leftToRight.index,
              ).clamp(0, ReadingDirection.values.length - 1),
              onSelected: (i) => _setInt(ReaderKeys.readingDirection, i),
            ),
            ChromeTile.choice(
              icon: Iconsax.arrow_swap_horizontal,
              title: 'Continuous direction',
              subtitle: 'Webtoons read top to bottom',
              labels: [for (final d in ReadingDirection.values) d.shortLabel],
              selectedIndex: _readerInt(
                ReaderKeys.webtoonDirection,
                ReadingDirection.topToBottom.index,
              ).clamp(0, ReadingDirection.values.length - 1),
              onSelected: (i) => _setInt(ReaderKeys.webtoonDirection, i),
            ),
            // These three read and write through `TapZoneSettings` rather
            // than naming a key and a default of their own. A row that
            // re-specifies the default is how a switch comes to show the
            // opposite of what the reader does, with each file perfectly
            // self-consistent — the `ReaderDefaults` lesson, one feature over.
            ChromeTile.toggle(
              icon: Iconsax.mouse_circle,
              title: 'Tap zones',
              subtitle: 'Tap the edges to turn pages, the middle for controls',
              value: TapZoneSettings.enabled,
              onChanged: (v) => setState(() => TapZoneSettings.setEnabled(v)),
            ),
            ChromeTile.toggle(
              icon: Iconsax.arrow_swap_horizontal,
              title: 'Mirror zones when reading backwards',
              subtitle: 'Keeps the forward zone on the side you read towards',
              value: TapZoneSettings.mirrorWhenReversed,
              onChanged: (v) =>
                  setState(() => TapZoneSettings.setMirrorWhenReversed(v)),
            ),
            ChromeTile.toggle(
              icon: Iconsax.mobile,
              title: 'Vibrate on a tap zone',
              subtitle:
                  'Confirms the tap landed, even on a zone that does nothing',
              value: TapZoneSettings.haptics,
              onChanged: (v) => setState(() => TapZoneSettings.setHaptics(v)),
            ),
            // Rebuilds on return, because the editor carries the same
            // enable switch and writes through the same setter. Without it
            // this screen would keep rendering the value it read on the way
            // in, and say the opposite of the screen it just opened -- the
            // `isReady` row, one feature over.
            // The display group. Every key behind these rows was declared in
            // `keys.dart` from the start and read by nothing -- the state
            // `FEATURES.md` exists to catch, where a checklist counting
            // declared keys reports parity for a feature nobody built.
            ChromeTile.choice(
              icon: Iconsax.gallery,
              title: 'Page background',
              subtitle: 'What sits behind a page that does not fill the screen',
              labels: [for (final b in ReaderBackground.values) b.label],
              selectedIndex: ReaderDisplaySettings.background.index,
              onSelected: (i) => setState(
                () => ReaderDisplaySettings.setBackground(
                  ReaderBackground.values[i],
                ),
              ),
            ),
            ChromeTile.toggle(
              icon: Iconsax.moon,
              title: 'Dim the page',
              // Named for what it does. AnymeX calls the same control
              // brightness while its slider only ever darkens -- raising the
              // screen needs the platform's own brightness and a plugin this
              // app does not carry, so "brightness" here would be a switch
              // promising something behind it that is not there.
              subtitle: 'Darkens the artwork without touching the controls',
              value: ReaderDisplaySettings.dimEnabled,
              onChanged: (v) =>
                  setState(() => ReaderDisplaySettings.setDimEnabled(v)),
            ),
            ChromeTile.slider(
              icon: Iconsax.sun_1,
              title: 'How much',
              value: ReaderDisplaySettings.dim.toDouble(),
              min: 0,
              max: ReaderDisplaySettings.maxDim.toDouble(),
              divisions: ReaderDisplaySettings.maxDim ~/ 5,
              valueLabel: '${ReaderDisplaySettings.dim}%',
              // Inert rather than hidden while the dim is off: a row that
              // vanishes takes its own explanation with it, and the switch
              // above has nothing left to point at.
              enabled: ReaderDisplaySettings.dimEnabled,
              onChanged: (v) =>
                  setState(() => ReaderDisplaySettings.setDim(v.round())),
            ),
            ChromeTile.toggle(
              icon: Iconsax.drop,
              title: 'Greyscale',
              subtitle: 'Drops colour from the artwork',
              value: ReaderDisplaySettings.greyscale,
              onChanged: (v) =>
                  setState(() => ReaderDisplaySettings.setGreyscale(v)),
            ),
            ChromeTile.toggle(
              icon: Iconsax.grid_1,
              title: 'Invert colours',
              // Composes with greyscale rather than replacing it, which is
              // the correction to AnymeX: its reader reads these as
              // `if (greyscale) ... else if (invert)`, so turning greyscale on
              // leaves a live invert switch doing nothing.
              subtitle: 'Combines with greyscale for an inverted grey page',
              value: ReaderDisplaySettings.invert,
              onChanged: (v) =>
                  setState(() => ReaderDisplaySettings.setInvert(v)),
            ),
            // A row rather than a switch, because the tint and the blend mode
            // are the setting -- a toggle alone would enable a colour nothing
            // on this screen can choose. Rebuilds on return for the same
            // reason the tap-zone row does: that screen carries the same
            // enable switch through the same setter.
            ChromeTile(
              icon: Iconsax.colorfilter,
              title: 'Colour filter',
              subtitle: ReaderDisplaySettings.filterEnabled
                  ? '${ReaderDisplaySettings.filterBlend.label}, over every page'
                  : 'Tint the page — a warm cast for reading at night',
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ColourFilterScreen(),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            ChromeTile(
              icon: Iconsax.mouse_square,
              title: 'Tap zone layout',
              subtitle: 'Which band does what, and where the edges fall',
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TapZoneEditorScreen(),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
            // Every row below decides what the *next* chapter does: the
            // reader applies them in `onInit` and releases them unconditionally
            // in `onClose`, so nothing here reaches a chapter already open.
            ChromeTile.choice(
              icon: Iconsax.rotate_left,
              title: 'Orientation',
              subtitle: 'How the reader sits when you turn the device',
              labels: [for (final o in ReaderOrientation.values) o.label],
              selectedIndex: _readerInt(
                ReaderKeys.orientationLock,
                ReaderDefaults.orientationLock,
              ).clamp(0, ReaderOrientation.values.length - 1),
              onSelected: (i) => _setInt(ReaderKeys.orientationLock, i),
            ),
            ChromeTile.toggle(
              icon: Iconsax.maximize_4,
              title: 'Full screen',
              subtitle: 'Hides the status and navigation bars while reading',
              value: _readerBool(
                ReaderKeys.immersiveMode,
                ReaderDefaults.immersiveMode,
              ),
              onChanged: (v) => _setBool(ReaderKeys.immersiveMode, v),
            ),
            ChromeTile.toggle(
              icon: Iconsax.eye_slash,
              title: 'Hide from screenshots',
              subtitle: 'Also blanks the reader in the app switcher',
              value: _readerBool(
                ReaderKeys.secureScreen,
                ReaderDefaults.secureScreen,
              ),
              onChanged: (v) => _setBool(ReaderKeys.secureScreen, v),
            ),
            // The e-ink pair, and they are two keys for the same reason the
            // dim's magnitude and switch are: "zero means off" loses the
            // duration every time the feature is toggled.
            ChromeTile.toggle(
              icon: Iconsax.refresh,
              title: 'E-ink refresh',
              subtitle:
                  'Flashes the screen after a page turn to clear '
                  'ghosting',
              value: _readerBool(
                ReaderKeys.displayRefreshEnabled,
                ReaderDefaults.displayRefresh,
              ),
              onChanged: (v) => _setBool(ReaderKeys.displayRefreshEnabled, v),
            ),
            if (_readerBool(
              ReaderKeys.displayRefreshEnabled,
              ReaderDefaults.displayRefresh,
            ))
              ChromeTile.slider(
                icon: Iconsax.timer_1,
                title: 'Flash length',
                value: _readerInt(
                  ReaderKeys.displayRefreshDurationMs,
                  ReaderDefaults.displayRefreshMs,
                ).toDouble(),
                min: 40,
                max: 400,
                divisions: 18,
                valueLabel:
                    '${_readerInt(ReaderKeys.displayRefreshDurationMs, ReaderDefaults.displayRefreshMs)} ms',
                onChanged: (v) =>
                    _setInt(ReaderKeys.displayRefreshDurationMs, v.round()),
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
          label: 'Library',
          children: [
            // The filter bar's gear is the other route, and it is the one a
            // reader will use day to day. This exists because that gear only
            // appears once a category does, so without it the screen that
            // *creates* the first one would be reachable only from a sheet on
            // a manga — a route nobody would guess at.
            ChromeTile(
              icon: Iconsax.folder_2,
              title: 'Categories',
              subtitle: 'Shelves to file your library into',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CategoriesScreen(),
                ),
              ),
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
