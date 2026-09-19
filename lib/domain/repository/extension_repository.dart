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

/// What happened the last time a repo's index was read, and when.
///
/// Persisted per repo, because "this repository has been failing for a week" is
/// the thing a user with several of them needs to see and the thing nothing in
/// the app could previously tell them. A refresh deliberately leaves the
/// previously known sources in place when it fails, which is right — a flaky
/// network must not empty the extension list — but it also means a dead repo
/// looks exactly like a healthy one until you notice it never gains anything.
///
/// **Absent is a third state, not a failure.** A repo added before this shipped,
/// or one whose refresh has never run, has no record — and "never checked" is
/// something the user can act on ("refresh it") in a way that "failed" is not.
/// Collapsing the two would report a working repo as broken.
///
/// The added/updated/removed counts from [RefreshResult] are deliberately *not*
/// stored. They describe one moment and go stale as soon as anything else
/// touches the catalogue, whereas how many sources a repo currently lists is
/// free to count from the loaded rows and is always true.
class RepoHealth {
  const RepoHealth({required this.checkedAt, this.error});

  /// When the index was last read, successfully or not.
  final DateTime checkedAt;

  /// Null when that read succeeded.
  final String? error;

  bool get isSuccess => error == null;

  Map<String, dynamic> toJson() => {
    'checkedAt': checkedAt.millisecondsSinceEpoch,
    if (error != null) 'error': error,
  };

  /// Returns null for a row this app did not write, rather than throwing.
  ///
  /// This is a disposable cache with a re-fetchable upstream: the worst a
  /// dropped row costs is one "Never checked" until the next refresh, which is
  /// a far better outcome than a corrupt entry taking out the repo sheet.
  static RepoHealth? fromJson(Map<String, dynamic> json) {
    final millis = json['checkedAt'];
    if (millis is! int) return null;
    final error = json['error'];
    return RepoHealth(
      checkedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      error: error is String ? error : null,
    );
  }
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

  /// Removes [url], deleting only the sources that are safe to delete.
  ///
  /// An **installed** source is *detached*, not deleted: its `repoUrl` is
  /// cleared, so it keeps working and simply stops receiving updates. Every
  /// library entry stores its source's id, and the user's chapters, progress
  /// and favourites all hang off that id — so deleting the row makes each of
  /// those entries fail with "No source with id ...", which the Kotlin app
  /// calls its highest-impact bug ever and which has no way back.
  ///
  /// Uninstalled sources are deleted outright; nothing points at them.
  ///
  /// This doc previously said the opposite — that installed sources went too —
  /// while the implementation has always detached them. It is recorded here
  /// because a doc that contradicts its implementation is worse than no doc:
  /// the next reader "fixes" the code to match and reintroduces the bug.
  Future<void> removeRepo(String url);

  /// Re-reads every configured repo index. Each repo is reported separately, so
  /// one unreachable repo does not hide the others' results.
  Future<List<RefreshResult>> refreshAll();

  Future<RefreshResult> refresh(String repoUrl);

  /// The last refresh outcome for each repo, keyed by URL.
  ///
  /// A repo with no entry has never been refreshed by this build. Entries for
  /// repos the user has since removed are dropped, so the map never outlives
  /// what [getRepos] returns.
  Future<Map<String, RepoHealth>> repoHealth();

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
