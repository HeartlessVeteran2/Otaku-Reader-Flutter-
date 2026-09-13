import 'package:isar_community/isar.dart';

part 'key_value.g.dart';

/// A single row of the app's key/value tier.
///
/// Every setting, every per-media scalar and every non-secret token lives here
/// rather than in SharedPreferences: Isar is already open, its sync API is fast
/// enough to read during `build()`, and one storage engine means one backup and
/// one recovery path. Secrets are the deliberate exception — those go to
/// `flutter_secure_storage`, never here.
@collection
class KeyValue {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  String? key;

  /// JSON of `{'val': <value>}`.
  ///
  /// The envelope exists so that `null`, `bool`, `num`, `String`, `List` and
  /// `Map` all round-trip through a single nullable `String` column. Storing the
  /// bare value would make a stored `null` and an absent row indistinguishable.
  String? value;
}
