import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/features/details/screens/manga_details_screen.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/features/library/widgets/library_card.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  LibraryController get _c => Get.find<LibraryController>();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Favourites change from Browse, which never touches this controller. The
    // shell keeps every tab alive in a LazyIndexedStack, so without a reload
    // the grid can show a library that is several additions out of date.
    if (state == AppLifecycleState.resumed) _c.load();
  }

  @override
  Widget build(BuildContext context) {
    final columns = (MediaQuery.sizeOf(context).width / 130).floor().clamp(
      2,
      6,
    );
    return OneUiScaffold(
      title: 'Library',
      onRefresh: _c.load,
      actions: [
        PopupMenuButton<LibrarySort>(
          icon: const Icon(Iconsax.sort),
          tooltip: 'Sort',
          onSelected: _c.setSort,
          itemBuilder: (context) => [
            for (final option in LibrarySort.values)
              PopupMenuItem(
                value: option,
                child: Obx(
                  () => Row(
                    children: [
                      Expanded(child: Text(_label(option))),
                      if (_c.sort.value == option)
                        Icon(
                          _c.ascending.value
                              ? Iconsax.arrow_up_2
                              : Iconsax.arrow_down,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _search,
            onChanged: _c.setQuery,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search your library',
              prefixIcon: const Icon(Iconsax.search_normal, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(OneUi.radiusSmall),
              ),
            ),
          ),
        ),
      ),
      slivers: [
        // The pull-to-refresh that each branch used to carry its own copy of
        // now lives on the scaffold, so the empty state is pullable without
        // wrapping it in a `ListView` that exists only to be scrollable.
        Obx(() {
          if (_c.isLoading.value && _c.entries.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final items = _c.visible;
          if (items.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(searching: _c.query.value.isNotEmpty),
            );
          }
          return SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 0.52,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _card(items[i]),
            ),
          );
        }),
      ],
    );
  }

  Widget _card(MangaEntry entry) {
    // The row stores the source's numeric id as a decimal string, never a hash,
    // so this converts straight back. Guarding anyway: a row written by a future
    // build with a different convention must not crash the grid.
    final sourceId = LibraryRepository.sourceIdOf(entry);
    return LibraryCard(
      entry: entry,
      unread: LibraryController.unreadOf(entry),
      sourceBaseUrl: _c.baseUrlFor(entry),
      onTap: sourceId == null
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MangaDetailsScreen(sourceId: sourceId, url: entry.url),
                ),
              );
              // Reading or un-favouriting happens behind the details page, so
              // the grid has to re-read on the way back.
              await _c.load();
            },
    );
  }

  static String _label(LibrarySort sort) => switch (sort) {
    LibrarySort.title => 'Title',
    LibrarySort.lastRead => 'Last read',
    LibrarySort.dateAdded => 'Date added',
    LibrarySort.unread => 'Unread count',
  };
}

/// The empty grid, as a box widget so a `SliverFillRemaining` can centre it.
///
/// Was previously a `ListView` whose only job was to be scrollable so the
/// pull-to-refresh worked; the scaffold owns the refresh now, so this is just
/// the message.
class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Iconsax.book, size: 40, color: theme.disabledColor),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            searching
                ? 'Nothing in your library matches that.'
                : 'Your library is empty.\nAdd a manga from Browse to '
                      'see it here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
