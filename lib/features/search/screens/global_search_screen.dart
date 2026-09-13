import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/screens/source_browse_screen.dart';
import 'package:otaku_reader/features/browse/widgets/manga_cover_card.dart';
import 'package:otaku_reader/features/details/screens/manga_details_screen.dart';
import 'package:otaku_reader/features/search/controllers/global_search_controller.dart';

/// Searches every installed source at once, one row per source.
///
/// [initialQuery] is what makes an AniList tile tappable: the home page knows a
/// title and nothing else, and this is the screen that turns a title into a
/// source that has it.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const _tag = 'global-search';

  late final GlobalSearchController _c = Get.put(
    GlobalSearchController(sources: Get.find<SourceRepository>()),
    tag: _tag,
  );
  late final TextEditingController _field = TextEditingController(
    text: widget.initialQuery ?? '',
  );

  @override
  void initState() {
    super.initState();
    final q = widget.initialQuery?.trim();
    if (q != null && q.isNotEmpty) _c.search(q);
  }

  @override
  void dispose() {
    _field.dispose();
    Get.delete<GlobalSearchController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _field,
          autofocus: widget.initialQuery == null,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search every source',
            border: InputBorder.none,
          ),
          onChanged: _c.onQueryChanged,
          onSubmitted: _c.search,
        ),
        actions: [
          Obx(
            () => _c.query.value.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Iconsax.close_circle),
                    tooltip: 'Clear',
                    onPressed: () {
                      _field.clear();
                      _c.search('');
                    },
                  ),
          ),
        ],
      ),
      body: Obx(() {
        final error = _c.error.value;
        if (error != null) {
          return _Message(icon: Iconsax.info_circle, text: error);
        }
        if (_c.results.isEmpty) {
          return const _Message(
            icon: Iconsax.search_normal,
            text: 'Type a title to search every installed source.',
          );
        }
        return ListView.builder(
          itemCount: _c.results.length,
          itemBuilder: (context, i) =>
              _SourceRow(result: _c.results[i], query: _c.query.value),
        );
      }),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.result, required this.query});

  final SourceSearchResult result;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceId = result.source.sourceId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  result.source.name,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (result.items.isNotEmpty)
                TextButton(
                  // The row is capped, so "see all" has to mean the source's
                  // own screen rather than a longer row here.
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SourceBrowseScreen(
                        sourceId: sourceId,
                        initialQuery: query,
                      ),
                    ),
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(height: 190, child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    if (result.isLoading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (result.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            // The source is named by the header above, so the message only has
            // to say what happened to it.
            'Search failed — the site may be down.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (result.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('No results', style: theme.textTheme.bodySmall),
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: result.items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (context, i) {
        final manga = result.items[i];
        return SizedBox(
          width: 112,
          child: MangaCoverCard(
            manga: manga,
            sourceBaseUrl: result.baseUrl,
            onTap: () {
              final url = manga.link;
              if (url == null) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MangaDetailsScreen(
                    sourceId: result.source.sourceId,
                    url: url,
                    initial: manga,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
