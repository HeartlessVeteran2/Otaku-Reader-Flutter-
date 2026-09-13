import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

/// A [SourceRepository] that knows about no sources at all.
///
/// Several suites need one only so a screen can ask for a cover's base URL and
/// be told there is none — the same path an entry whose extension was
/// uninstalled takes in production. Shared rather than copied per suite: when
/// the interface gains a method, one copy compiles and the others silently
/// drift out of step with what they claim to stand in for.
class NoSources implements SourceRepository {
  const NoSources();

  @override
  Future<Source?> sourceById(int id) async => null;

  @override
  Future<SourceMethods> methodsFor(int id) async =>
      throw StateError('No source with id $id');

  @override
  Future<void> markUsed(int id) async {}

  @override
  void evict(int id) {}

  @override
  void evictAll() {}

  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
}
