import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/screens/accounts_screen.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';

/// Appearance, reader defaults and source behaviour.
///
/// Every control here writes through immediately. There is no Save button, so
/// there is no state to lose and nothing to reconcile if the app is killed
/// mid-change.
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
    return OneUiScaffold(
      title: 'Settings',
      slivers: [
        SliverOneUiGroup(
          label: 'Appearance',
          children: [
            Obx(
              () => ListTile(
                leading: const Icon(Iconsax.moon),
                title: const Text('Theme'),
                subtitle: Text(switch (_theme.themeMode.value) {
                  ThemeMode.system => 'Follow the system',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                onTap: _pickThemeMode,
              ),
            ),
            Obx(
              () => SwitchListTile(
                secondary: const Icon(Iconsax.mobile),
                title: const Text('Pure black dark theme'),
                subtitle: const Text('Saves power on OLED screens'),
                value: _theme.isOled.value,
                onChanged: _theme.setOled,
              ),
            ),
            Obx(
              () => ListTile(
                leading: const Icon(Iconsax.colorfilter),
                title: const Text('Colour source'),
                subtitle: Text(switch (_theme.source.value) {
                  ThemeSource.standard => 'App default',
                  ThemeSource.dynamicColor =>
                    'Material You (from the wallpaper)',
                  ThemeSource.custom => 'Custom',
                }),
                onTap: _pickColourSource,
              ),
            ),
            Obx(
              () => SwitchListTile(
                secondary: const Icon(Iconsax.brush_2),
                title: const Text('Tint from the cover'),
                subtitle: const Text('The manga you have open colours the app'),
                value: _theme.useCoverColor.value,
                onChanged: _theme.setUseCoverColor,
              ),
            ),
          ],
        ),
        SliverOneUiGroup(
          label: 'Reader defaults',
          children: [
            ListTile(
              leading: const Icon(Iconsax.book_1),
              title: const Text('Reading layout'),
              subtitle: Text(
                _readerInt(ReaderKeys.readingLayout, 0) ==
                        ReadingLayout.webtoon.index
                    ? 'Webtoon (continuous)'
                    : 'Paged',
              ),
              // A default, not an override: a manga already opened keeps whatever
              // it was last read with, because that choice was made per series.
              onTap: () => _pick<int>(
                title: 'Reading layout',
                current: _readerInt(ReaderKeys.readingLayout, 0),
                options: const {0: 'Paged', 1: 'Webtoon (continuous)'},
                onPicked: (v) => _setInt(ReaderKeys.readingLayout, v),
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.arrow_swap_horizontal),
              title: const Text('Reading direction'),
              subtitle: Text(switch (_readerInt(
                ReaderKeys.readingDirection,
                0,
              )) {
                1 => 'Right to left',
                _ => 'Left to right',
              }),
              onTap: () => _pick<int>(
                title: 'Reading direction',
                current: _readerInt(ReaderKeys.readingDirection, 0),
                options: const {
                  0: 'Left to right',
                  1: 'Right to left (most manga)',
                },
                onPicked: (v) => _setInt(ReaderKeys.readingDirection, v),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Iconsax.sun_1),
              title: const Text('Keep the screen on'),
              value: _readerBool(ReaderKeys.keepScreenOn, true),
              onChanged: (v) => _setBool(ReaderKeys.keepScreenOn, v),
            ),
            SwitchListTile(
              secondary: const Icon(Iconsax.document),
              title: const Text('Show the page number'),
              value: _readerBool(ReaderKeys.showPageIndicator, true),
              onChanged: (v) => _setBool(ReaderKeys.showPageIndicator, v),
            ),
          ],
        ),
        SliverOneUiGroup(
          label: 'Sources',
          children: [
            Obx(
              () => SwitchListTile(
                secondary: const Icon(Iconsax.eye_slash),
                title: const Text('Show 18+ sources'),
                subtitle: const Text(
                  'Also hides adult titles from the home page',
                ),
                // Reads and writes the shared holder, not the key directly.
                // Writing the key alone flipped the stored value while the live
                // Home and Browse controllers carried on with their own copies,
                // so the setting appeared to do nothing until a restart.
                value: Get.find<NsfwPreference>().shown.value,
                onChanged: Get.find<NsfwPreference>().setShown,
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.info_circle),
              title: const Text('Extensions and repositories'),
              subtitle: const Text('Manage these from the Browse tab'),
              enabled: false,
            ),
          ],
        ),
        SliverOneUiGroup(
          label: 'Accounts',
          children: [
            Obx(() {
              final auth = Get.find<AniListAuth>();
              final viewer = auth.viewer.value;
              return ListTile(
                leading: const Icon(Iconsax.user_octagon),
                title: const Text('AniList'),
                // Three states, not two. A build with no client id is not
                // "not signed in" — there is nothing to sign in to — and
                // saying so here would contradict the screen this row opens.
                subtitle: Text(
                  !auth.isConfigured
                      ? 'Not set up in this build'
                      : viewer == null
                      ? 'Not signed in'
                      : 'Signed in as ${viewer.name}',
                ),
                trailing: const Icon(Icons.chevron_right),
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

  Future<void> _pickThemeMode() => _pick<ThemeMode>(
    title: 'Theme',
    current: _theme.themeMode.value,
    options: const {
      ThemeMode.system: 'Follow the system',
      ThemeMode.light: 'Light',
      ThemeMode.dark: 'Dark',
    },
    onPicked: _theme.setThemeMode,
  );

  Future<void> _pickColourSource() => _pick<ThemeSource>(
    title: 'Colour source',
    current: _theme.source.value,
    options: const {
      ThemeSource.standard: 'App default',
      ThemeSource.dynamicColor: 'Material You (from the wallpaper)',
      ThemeSource.custom: 'Custom',
    },
    onPicked: _theme.setSource,
  );

  /// One radio dialog for every single-choice setting on this screen.
  Future<void> _pick<T>({
    required String title,
    required T current,
    required Map<T, String> options,
    required void Function(T) onPicked,
  }) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          // A RadioGroup ancestor rather than per-tile `groupValue`/`onChanged`:
          // those are deprecated, and one selection handler for the whole set
          // is also the only place a "which one is chosen" bug can live.
          RadioGroup<T>(
            groupValue: current,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options.entries)
                  RadioListTile<T>(
                    value: option.key,
                    title: Text(option.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }
}
