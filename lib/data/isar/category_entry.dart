import 'package:isar_community/isar.dart';

part 'category_entry.g.dart';

@collection
class CategoryEntry {
  Id id = Isar.autoIncrement;

  late String name;

  int order = 0;

  /// Hidden categories are omitted from the library tabs until unlocked —
  /// Komikku's "conceal content from others" behaviour.
  bool hidden = false;
}
