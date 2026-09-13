import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/source_browse_controller.dart';
import 'package:otaku_reader/features/browse/widgets/manga_cover_card.dart';
import 'package:otaku_reader/features/details/screens/manga_details_screen.dart';

/// Browses one installed source: popular, latest, or a search.
class SourceBrowseScreen extends StatefulWidget {
  const SourceBrowseScreen({
    super.key,
    required this.sourceId,
    this.initialQuery,
  });

  final int sourceId;

  /// Opens straight into a search rather than the popular listing — what "See
  /// all" on a global search result means.
  final String? initialQuery;

  @override
  State<SourceBrowseScreen> createState() => _SourceBrowseScreenState();
}

class _SourceBrowseScreenState extends State<SourceBrowseScreen> {
  late final String _tag = 'browse-${widget.sourceId}';
  late final SourceBrowseController _c = Get.put(
    SourceBrowseController(
      sources: Get.find<SourceRepository>(),
      sourceId: widget.sourceId,
      initialQuery: widget.initialQuery,
    ),
    tag: _tag,
  );
  final _scroll = ScrollController();
  late final _search = TextEditingController(text: widget.initialQuery ?? '');

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    Get.delete<SourceBrowseController>(tag: _tag);
    super.dispose();
  }

  void _onScroll() {
    // Pre-fetch a screenful early rather than at the exact bottom, so the grid
    // does not visibly stall at the end of every page.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _c.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final columns = _columnsFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(_c.source.value?.name ?? 'Browse')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _c.setQuery,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search this source',
                    prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                    // Bound to the controller, not read once: a plain
                    // `_search.text` check does not rebuild on typing or on a
                    // programmatic `clear()`, so the button appeared and
                    // disappeared a keystroke late.
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _search,
                      builder: (context, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _search.clear();
                                _c.setQuery('');
                              },
                            ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Obx(
                () => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Popular'),
                        selected: _c.mode.value == BrowseMode.popular,
                        onSelected: (_) => _c.setMode(BrowseMode.popular),
                      ),
                      if (_c.supportsLatest.value)
                        ChoiceChip(
                          label: const Text('Latest'),
                          selected: _c.mode.value == BrowseMode.latest,
                          onSelected: (_) => _c.setMode(BrowseMode.latest),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Obx(() {
        if (_c.isLoading.value && _c.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = _c.error.value;
        if (error != null && _c.items.isEmpty) {
          return _SourceError(message: error, onRetry: _c.reload);
        }
        // A failed refresh keeps the previous results, so the failure would
        // otherwise be invisible -- the user would see a stale grid and no hint
        // that the reload did not work.
        final banner = error == null
            ? null
            : _RefreshFailedBanner(onRetry: _c.reload);
        if (_c.items.isEmpty) {
          // Wrapped so a source that legitimately returns nothing can still be
          // retried; a bare centred message is a dead end.
          return RefreshIndicator(
            onRefresh: _c.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),
                _Empty(searching: _c.mode.value == BrowseMode.search),
              ],
            ),
          );
        }

        final baseUrl = _c.effectiveBaseUrl.value;
        final paging = _c.pagingError.value;
        return Column(
          children: [
            if (banner != null) banner,
            Expanded(
              child: RefreshIndicator(
                onRefresh: _c.reload,
                child: GridView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 0.52,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 12,
                  ),
                  itemCount:
                      _c.items.length + (_c.isLoadingMore.value ? columns : 0),
                  itemBuilder: (context, i) {
                    if (i >= _c.items.length) {
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final manga = _c.items[i];
                    final link = manga.link;
                    return MangaCoverCard(
                      manga: manga,
                      sourceBaseUrl: baseUrl,
                      // A listing entry with no link cannot be opened. Sources do
                      // emit them, and a tap that silently does nothing is worse
                      // than a tile that plainly is not tappable.
                      onTap: link == null || link.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MangaDetailsScreen(
                                  sourceId: widget.sourceId,
                                  url: link,
                                  initial: manga,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ),
            // At the foot, not as a banner at the top: what failed is the
            // *next* page, which is where the user is looking, and the retry
            // continues from there rather than reloading page 1 and throwing
            // away everything already listed.
            if (paging != null) _PagingFailed(onRetry: _c.retryPaging),
          ],
        );
      }),
    );
  }

  /// Honours the user's grid-size preference, but still adapts to width so a
  /// phone setting does not produce postage stamps on a tablet.
  int _columnsFor(double width) {
    final preferred = LibraryKeys.gridSize.get<int>(3);
    final fit = (width / 130).floor();
    return fit.clamp(2, preferred.clamp(2, 6) + 2);
  }
}

/// Shown above a retained grid when a refresh failed.
class _RefreshFailedBanner extends StatelessWidget {
  const _RefreshFailedBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Iconsax.warning_2, size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could not refresh. Showing the last results.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'Retry',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceError extends StatelessWidget {
  const _SourceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Iconsax.cloud_cross,
            size: 40,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

/// Shown under the grid when loading the *next* page failed.
class _PagingFailed extends StatelessWidget {
  const _PagingFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Could not load more. The site may be down.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      searching ? 'No results.' : 'This source returned nothing.',
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}
