import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Obx(() {
        if (_c.isLoading.value && _c.entries.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = _c.visible;
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                Icon(
                  Iconsax.book,
                  size: 40,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _c.query.value.isNotEmpty
                        ? 'Nothing in your library matches that.'
                        : 'Your library is empty.\nAdd a manga from Browse to '
                              'see it here.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _c.load,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
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
