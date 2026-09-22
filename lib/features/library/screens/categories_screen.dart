import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';

/// Create, rename, delete and reorder the library's categories.
///
/// AnymeX's equivalent is `screens/library/editor/list_editor.dart` (1,244
/// lines), and three of its decisions are taken here: a `ReorderableListView`
/// with **explicit** drag handles, a create affordance in the bottom third,
/// and rename and delete as dialogs off each row. What is not taken is its
/// reorder *mode* — a button that turns dragging on. With
/// `buildDefaultDragHandles: false` and a handle on every row there is nothing
/// for the mode to disambiguate, so it is a state the user has to discover and
/// then leave.
///
/// It also does not manage *membership* from here. AnymeX opens a media
/// editor sheet per list; the manga is the thing the user is thinking about
/// when they file it, so that lives on the details screen instead.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoryRepository get _repo => Get.find<CategoryRepository>();
  LibraryController get _library => Get.find<LibraryController>();

  /// The screen's own copy, so a drag can reorder optimistically.
  ///
  /// Reading `LibraryController.categories` directly would make every drag
  /// wait for a database round trip before the row moved, which reads as the
  /// gesture not registering.
  List<CategoryEntry> _categories = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _categories = _repo.all();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold.slivers(
      title: 'Categories',
      onRefresh: () async => _reload(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Iconsax.add),
        label: const Text('New category'),
      ),
      slivers: [
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_categories.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: _Empty())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Chrome.gutter,
              Chrome.gap,
              Chrome.gutter,
              // Clear of the extended FAB, which otherwise sits on the last
              // row's delete button -- the one row where a mis-tap is
              // destructive.
              96,
            ),
            sliver: SliverReorderableList(
              itemCount: _categories.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) =>
                  _row(context, _categories[index], index),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, CategoryEntry category, int index) {
    final counts = _library.categoryCounts;
    final count = counts[category.id] ?? 0;

    return Padding(
      // Keyed on the row's identity, not its position. A key that is the index
      // survives a reorder unchanged, so Flutter matches the old element to
      // the new row and the drag animates the wrong card.
      key: ValueKey(category.id),
      padding: const EdgeInsets.only(bottom: Chrome.gap),
      child: ChromeTile(
        title: category.name,
        subtitle: count == 1 ? '1 manga' : '$count manga',
        icon: Iconsax.folder_2,
        showChevron: false,
        onTap: () => _rename(category),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Iconsax.trash, size: 18),
              tooltip: 'Delete',
              onPressed: () => _delete(category, count),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Icon(Icons.drag_handle_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    // `onReorderItem`, not the deprecated `onReorder` — and the difference is
    // a line that has to be *absent*. `onReorder` reports the destination as
    // an index into the list before the item is removed, so it needs a
    // `if (oldIndex < newIndex) newIndex -= 1;` correction; `onReorderItem`
    // has already applied it. Carrying that line across the migration puts
    // every downward drag one row short, silently, with no error and nothing
    // to fail.
    setState(() {
      final moved = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, moved);
    });
    unawaited(HapticFeedback.mediumImpact());

    _repo.reorder([for (final c in _categories) c.id]);
    // Re-read rather than trusting the optimistic list: the repository is the
    // one that decides what the order actually became, and it has rules of its
    // own about ids it was not given.
    _reload();
  }

  Future<void> _create() async {
    final name = await _promptName(title: 'New category', confirm: 'Create');
    if (name == null) return;
    _repo.create(name);
    _reload();
  }

  Future<void> _rename(CategoryEntry category) async {
    final name = await _promptName(
      title: 'Rename category',
      confirm: 'Rename',
      initial: category.name,
    );
    if (name == null) return;
    _repo.rename(category.id, name);
    _reload();
  }

  Future<void> _delete(CategoryEntry category, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${category.name}"?'),
        content: Text(
          count == 0
              // Two sentences for two different situations. "Nothing is filed
              // here" is the reassurance; the other is the warning, and
              // collapsing them into one line loses whichever the user needed.
              ? 'Nothing is filed in this category.'
              : 'The ${count == 1 ? 'manga' : '$count manga'} in it '
                    '${count == 1 ? 'stays' : 'stay'} in your library — only '
                    'the category goes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    // `?? false`: a barrier dismiss pops null, and reading that as yes would
    // delete a category for a tap next to the dialog.
    if (!(ok ?? false)) return;

    _repo.delete(category.id);
    _reload();
  }

  /// Returns the trimmed name, or null if the user backed out.
  Future<String?> _promptName({
    required String title,
    required String confirm,
    String? initial,
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(title: title, confirm: confirm, initial: initial),
  );
}

/// A dialog that owns its own `TextEditingController`.
///
/// Deliberately a `StatefulWidget` rather than a controller created by the
/// caller and disposed after the `await`. That future completes when the route
/// is **popped**, while the exit animation is still running and the field is
/// still mounted, so disposing there throws part-way through the close — a
/// defect already in `CLAUDE.md`, invisible to a test that asserts only the
/// end state. The framework disposes this one once the route is gone, which
/// also covers a barrier dismiss.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.confirm, this.initial});

  final String title;
  final String confirm;
  final String? initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _name.text.trim();
    // The repository refuses a blank name too. Refusing here as well is what
    // keeps the dialog open instead of closing on a tap that does nothing --
    // the two checks answer different questions.
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'Reading, Favourites, On hold…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        // Enabled state follows the field, so the button cannot look live
        // while `_submit` would refuse.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _name,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirm),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Iconsax.folder_open, size: 40, color: theme.disabledColor),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No categories yet.\nMake one to file your library into shelves — '
            'a manga can be in several at once.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
