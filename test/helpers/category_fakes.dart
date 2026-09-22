import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';

/// A `CategoryRepository` that holds nothing.
///
/// For the suites that are about something else entirely — the app shell, the
/// chrome, the library grid's sorting. Requiring a real one there would make
/// standing up a database a precondition for rendering a screen, which is the
/// `ChromeMetrics` argument: a test should not have to opt into a feature it
/// is not testing.
///
/// It answers an **empty list**, which is the state a fresh install is in, so
/// a screen built on it renders the no-categories branch rather than a
/// half-populated one nothing asked for.
class EmptyCategories implements CategoryRepository {
  const EmptyCategories();

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  List<CategoryEntry> all() => const [];

  @override
  CategoryEntry? create(String name) => null;

  @override
  bool rename(int id, String name) => false;

  @override
  void delete(int id) {}

  @override
  void reorder(List<int> ids) {}

  @override
  List<int> categoriesOf(int sourceId, String url) => const [];

  @override
  void setCategoriesFor(int s, String url, List<int> ids) {}
}
