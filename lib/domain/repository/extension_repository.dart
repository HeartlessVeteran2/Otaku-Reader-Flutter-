import 'package:otaku_reader/source/model/source.dart';

/// Where an extension index lives, and what the app calls it.
///
/// A repo is just a URL to an `index.json`. It is modelled as a value rather
/// than an Isar row because the set is small, user-owned, and belongs with the
/// rest of the user's settings in the key/value tier.
class ExtensionRepo {
  const ExtensionRepo({required this.url, this.name});

  final String url;
  final String? name;

  Map<String, dynamic> toJson() => {'url': url, if (name != null) 'name': name};

  static ExtensionRepo fromJson(Map<String, dynamic> json) =>
      ExtensionRepo(url: json['url'] as String, name: json['name'] as String?);

  @override
  bool operator ==(Object other) =>
      other is ExtensionRepo && other.url == url && other.name == name;

  @override
  int get hashCode => Object.hash(url, name);
}

/// What a refresh of one repo did, so the UI can say something specific.
///
/// A refresh that reaches the network and finds nothing is not the same as one
/// that could not reach the network, and a user staring at an empty extension
/// list needs to be told which happened.
class RefreshResult {
  const RefreshResult({
    required this.repoUrl,
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.error,
  });

  final String repoUrl;
  final int added;
  final int updated;
  final int removed;

  /// Null on success. A transport failure, a non-200, or an index that is not
  /// a JSON list — all of which leave the previously known sources in place.
  final String? error;

  bool get isSuccess => error == null;
}

/// Manages extension repositories and the extensions they list.
///
/// Kept an interface so the domain layer does not depend on Isar, GetX or
/// `package:http`; the implementation is the only thing that knows about those.
abstract interface class ExtensionRepository {
  Future<List<ExtensionRepo>> getRepos();

  /// Adds [repo] and refreshes it. Adding an already-present URL refreshes it
  /// rather than duplicating it.
  Future<RefreshResult> addRepo(ExtensionRepo repo);

  /// Removes [url] and deletes the sources that came from it.
  ///
  /// Installed sources go too: leaving them would strand rows whose origin the
  /// user has explicitly removed, and whose updates can never arrive again.
  Future<void> removeRepo(String url);

  /// Re-reads every configured repo index. Each repo is reported separately, so
  /// one unreachable repo does not hide the others' results.
  Future<List<RefreshResult>> refreshAll();

  Future<RefreshResult> refresh(String repoUrl);

  /// Every known extension, installed or not.
  Future<List<Source>> listAll();

  /// Downloads [source]'s code and marks it installed.
  Future<Source> install(Source source);

  /// Re-downloads the code for a source whose index version moved on.
  Future<Source> update(Source source);

  /// Drops the code but keeps the index row, so the entry stays browsable and
  /// re-installable rather than vanishing from the list.
  Future<Source> uninstall(Source source);
}
