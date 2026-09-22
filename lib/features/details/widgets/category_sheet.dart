import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';

/// Files a manga into categories — AnymeX's `CustomListDialog`.
///
/// Three things are taken from it: a checkbox per category with a count under
/// the name, a search field that appears only once the list is long enough to
/// need one, and a **create** affordance inside the sheet, so the first
/// category can be made where the user is already thinking about filing
/// something rather than by going to find a settings screen.
///
/// One thing is deliberately not taken. AnymeX keys its before/after map by
/// `listName`, so two lists with the same name share one entry and toggling
/// either writes the other. Names are duplicable here on purpose — two
/// categories called "Reading" are a mess the user can see and fix, where a
/// silent refusal reads as a broken button — which makes the name an unsafe
/// key. This keys by id.
///
/// Returns true if anything was saved, so the caller can refresh.
Future<bool> showCategorySheet({
  required BuildContext context,
  required CategoryRepository repository,
  required int sourceId,
  required String url,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(context.radius(Chrome.cardRadius)),
      ),
    ),
    builder: (_) =>
        _CategorySheet(repository: repository, sourceId: sourceId, url: url),
  );
  return saved ?? false;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({
    required this.repository,
    required this.sourceId,
    required this.url,
  });

  final CategoryRepository repository;
  final int sourceId;
  final String url;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  /// The sheet owns this, rather than the caller creating one beside
  /// `showModalBottomSheet` and disposing it after the await. That future
  /// completes when the route is *popped*, with the exit animation still
  /// running and the field still mounted — see `CLAUDE.md`.
  final _search = TextEditingController();

  List<CategoryEntry> _categories = const [];

  /// Ids ticked right now. Seeded from the row and edited locally, so Cancel
  /// genuinely cancels.
  Set<int> _checked = {};

  /// What the row held when the sheet opened, so Save can tell an edit from a
  /// no-op and skip the write entirely.
  Set<int> _initial = {};

  bool _loading = true;
  String _query = '';

  /// Above this many categories the sheet grows a search field. AnymeX's
  /// number, and its reason holds: a search box over three rows costs more
  /// height than it saves scrolling.
  static const _searchThreshold = 3;

  @override
  void initState() {
    super.initState();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    final current = widget.repository.categoriesOf(widget.sourceId, widget.url);
    setState(() {
      _categories = widget.repository.all();
      _initial = current.toSet();
      _checked = current.toSet();
      _loading = false;
    });
  }

  List<CategoryEntry> get _visible => _query.isEmpty
      ? _categories
      : _categories
            .where((c) => c.name.toLowerCase().contains(_query))
            .toList();

  void _save() {
    // Nothing changed, so nothing is written. A `setCategoriesFor` that runs
    // anyway announces a change to every listener and makes the grid reload
    // for a sheet the user only looked at.
    if (!setEquals(_checked, _initial)) {
      widget.repository.setCategoriesFor(
        widget.sourceId,
        widget.url,
        // In the categories' own order rather than tap order, so the stored
        // list reads the same as the screen that manages them.
        [
          for (final c in _categories)
            if (_checked.contains(c.id)) c.id,
        ],
      );
    }
    Navigator.pop(context, true);
  }

  Future<void> _create() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _NewCategoryDialog(),
    );
    if (name == null) return;

    if (!mounted) return;
    final created = widget.repository.create(name);
    if (created == null) return;
    setState(() {
      _categories = widget.repository.all();
      // Ticked on creation: making a category from inside this sheet is an
      // action about *this* manga, so leaving it unticked would ask the user
      // to say the same thing twice.
      _checked = {..._checked, created.id};
    });
    // Deliberately **not** `_load()`. That re-seeds `_initial` from the row as
    // well, and `_initial` is what Save compares against to decide whether
    // anything changed — so re-seeding it here would make the new tick look
    // like the state the sheet opened in, and Save would write nothing at all.
    // It also re-seeds `_checked` from the row, wiping the tick two lines up.
    // Found by a test that got as far as asserting the tick and then read a
    // database with nothing in it.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        // A share of the viewport, not a constant: a sheet sized for a phone
        // is a band across a tablet, and one sized in pixels vanishes in split
        // screen. Guarded against a zero height for the same reason the
        // tap-zone preview is — at zero, remove the cap rather than apply it,
        // because "too small to see" and "not there" render identically.
        constraints: BoxConstraints(
          maxHeight: media.size.height > 0
              ? media.size.height * 0.7
              : double.infinity,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Chrome.gutter, 0, 16, 8),
              child: Row(
                children: [
                  Text('Categories', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              )
            else ...[
              if (_categories.length > _searchThreshold)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Chrome.gutter,
                    0,
                    Chrome.gutter,
                    8,
                  ),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Iconsax.search_normal_1, size: 18),
                      hintText: 'Find a category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              Flexible(
                child: _visible.isEmpty
                    ? _Empty(searching: _query.isNotEmpty)
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Chrome.gutter,
                        ),
                        children: [
                          for (final category in _visible)
                            CheckboxListTile(
                              key: ValueKey(category.id),
                              value: _checked.contains(category.id),
                              title: Text(category.name),
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (on) => setState(() {
                                final next = {..._checked};
                                if (on ?? false) {
                                  next.add(category.id);
                                } else {
                                  next.remove(category.id);
                                }
                                _checked = next;
                              }),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Chrome.gutter,
                  4,
                  Chrome.gutter,
                  Chrome.gutter,
                ),
                child: OutlinedButton.icon(
                  onPressed: _create,
                  icon: const Icon(Iconsax.add, size: 18),
                  label: const Text('New category'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ],
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
    child: Text(
      // Two different answers. "Nothing matches" is a search that missed;
      // "none yet" is a state the user can act on, and the button below says
      // how.
      searching
          ? 'No category matches that.'
          : 'No categories yet. Make one to file this into a shelf.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New category'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _name,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : _submit,
          child: const Text('Create'),
        ),
      ),
    ],
  );
}
