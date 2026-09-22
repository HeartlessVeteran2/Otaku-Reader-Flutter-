import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/core/widgets/chrome_pills.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';

/// The library's category filter — AnymeX's `ChipTabs`.
///
/// Ported structurally, including where it lives: AnymeX hangs it off its
/// header's `bottom` slot rather than putting it in the scroll body, so it
/// stays reachable while the grid scrolls and slides away with the header
/// rather than separately. This app's [ChromeScaffold] already has that slot.
///
/// Two departures, both because the reference's answers do not survive here:
///
/// - **Selection is by id, not by index.** AnymeX stores
///   `selectedListIndex` and clamps it to the list length when a list
///   disappears, which silently moves the user to a *different* category. An
///   id that names nothing is dropped instead, which shows the whole library
///   — the honest answer, and the one that cannot be mistaken for a wipe.
/// - **An empty category still gets a pill.** AnymeX hides one unless it is
///   selected. A category is empty precisely when it has just been created,
///   so hiding it means making one and not finding it. The count is what
///   makes that legible rather than confusing.
class CategoryFilterBar extends StatelessWidget implements PreferredSizeWidget {
  const CategoryFilterBar({
    super.key,
    required this.controller,
    required this.onManage,
  });

  final LibraryController controller;
  final VoidCallback onManage;

  /// The row's own height, plus the gap the header puts above it.
  static const rowHeight = 38.0;

  /// A **first-frame estimate**, like everything else handed to this slot.
  ///
  /// It cannot be reactive: the scaffold reads it outside any `Obx`, so it
  /// still claims a row on the frame where the last category was deleted.
  /// That is exactly what `ChromeScaffold`'s measurement is for — the real
  /// height arrives the next frame and the body moves with it. Stated here
  /// because the alternative is trying to make this getter observe an `RxList`
  /// from outside a reactive build, which cannot work and would fail silently.
  @override
  Size get preferredSize => const Size.fromHeight(rowHeight);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final categories = controller.categories;
      // Nothing to filter against. A lone "All" chip over an empty set is a
      // control whose only option is the state you are already in.
      if (categories.isEmpty) return const SizedBox.shrink();

      final selected = controller.selectedCategory.value;
      final counts = controller.categoryCounts;

      return SizedBox(
        height: rowHeight,
        child: Row(
          children: [
            const SizedBox(width: Chrome.gutter),
            _ManageButton(onTap: onManage),
            const SizedBox(width: Chrome.gap),
            Expanded(
              child: ChromePills(
                // The gutter is already spent on the button, so the scroller
                // starts flush and only pads its trailing edge.
                padding: const EdgeInsets.only(right: Chrome.gutter),
                pills: [
                  ChromePill(
                    label: 'All',
                    count: controller.entries.length,
                    selected: selected == null,
                    onTap: () => controller.selectCategory(null),
                  ),
                  for (final category in categories)
                    ChromePill(
                      label: category.name,
                      // Absent means none filed, which is a real answer for a
                      // category that exists and is empty.
                      count: counts[category.id] ?? 0,
                      selected: selected == category.id,
                      onTap: () => controller.selectCategory(category.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// The gear that opens the management screen.
///
/// Beside the pills rather than in the header's actions pill, which is
/// AnymeX's placement and is load-bearing here: the Library header already
/// carries a leading avatar, a sort action and search, and the measured
/// budget in `CLAUDE.md` puts a leading plus three actions over the edge at
/// 320 and 360. This costs no header slot at all.
class _ManageButton extends StatelessWidget {
  const _ManageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Manage categories',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(context.radius(12)),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.08),
              width: Chrome.pillBorder,
            ),
          ),
          child: Icon(
            Iconsax.setting_4,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
