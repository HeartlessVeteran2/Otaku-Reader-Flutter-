// A live end-to-end check of the source runtime.
//
// Lives in tool/ rather than test/ on purpose: `flutter test` only collects
// `test/**_test.dart`, so this never gates a build. It needs the open internet
// and third-party sites, both of which fail for reasons that have nothing to do
// with this code. Run it by hand:
//
//     flutter test tool/source_sweep.dart --plain-name sweep
//     flutter test tool/source_sweep.dart --dart-define=SOURCE=madara
//
// It chains getPopular -> getDetail -> getPageList. Running only getPopular is
// how a source scores a pass while producing entries that lead nowhere.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/runtime/dart_source_runtime.dart';

const _indexUrl =
    'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json';

Future<String> _fetch(String url) async {
  final client = HttpClient()..userAgent = 'otaku-reader-sweep';
  final req = await client.getUrl(Uri.parse(url));
  final res = await req.close();
  return res.transform(utf8.decoder).join();
}

void main() {
  // Sources read their preferences on the very first call -- a Madara mirror
  // override is read inside getPopular -- so the KV store has to be live before
  // any source runs. The app guarantees this by opening Isar in main() before
  // any controller exists; the sweep has to do the same by hand.
  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    final dir = await Directory.systemTemp.createTemp('otaku_sweep');
    db.isar = Isar.openSync(
      [KeyValueSchema],
      directory: dir.path,
      name: 'sweep',
      inspector: false,
    );
  });

  tearDownAll(() async => db.isar.close(deleteFromDisk: true));

  test('sweep', _sweep, timeout: const Timeout(Duration(minutes: 20)));
}

Future<void> _sweep() async {
  const filter = String.fromEnvironment('SOURCE');
  final wanted = filter.isEmpty ? null : filter.toLowerCase();

  stdout.writeln('fetching index...');
  final index = jsonDecode(await _fetch(_indexUrl)) as List;

  final dart = index
      .map((e) => Source.fromIndexJson((e as Map).cast<String, dynamic>()))
      .where((s) => s.sourceCodeLanguage == SourceCodeLanguage.dart)
      .where((s) => s.lang == 'en' || s.lang == 'all')
      // Match the script URL as well as the name: the multisrc templates are
      // named after their *site* ("Azure Scans"), so filtering on name alone
      // never finds "madara".
      .where(
        (s) =>
            wanted == null ||
            s.name.toLowerCase().contains(wanted) ||
            (s.sourceCodeUrl ?? '').toLowerCase().contains(wanted),
      )
      .toList();

  const limitRaw = String.fromEnvironment('LIMIT');
  final limit = int.tryParse(limitRaw) ?? dart.length;
  final selected = dart.take(limit).toList();
  stdout.writeln(
    '${dart.length} candidate Dart sources, sweeping ${selected.length}\n',
  );

  final scriptCache = <String, String>{};
  var evaluated = 0, popular = 0, detail = 0, pages = 0;

  for (final source in selected) {
    final url = source.sourceCodeUrl;
    if (url == null) continue;
    stdout.write('${source.name.padRight(28)} ');
    try {
      source.sourceCode = scriptCache[url] ??= await _fetch(url);
      final runtime = DartSourceRuntime(source);
      evaluated++;
      stdout.write('eval:ok ');

      final list = await runtime.getPopular(1);
      if (list.list.isEmpty) {
        stdout.writeln('popular:EMPTY');
        runtime.dispose();
        continue;
      }
      popular++;
      stdout.write('popular:${list.list.length} ');

      final manga = await runtime.getDetail(list.list.first.link!);
      final chapters = manga.chapters ?? const [];
      if (chapters.isEmpty) {
        stdout.writeln('detail:NO-CHAPTERS');
        runtime.dispose();
        continue;
      }
      detail++;
      stdout.write('chapters:${chapters.length} ');

      final pageList = await runtime.getPageList(chapters.first.url!);
      if (pageList.isEmpty) {
        stdout.writeln('pages:EMPTY');
      } else {
        pages++;
        stdout.writeln('pages:${pageList.length} OK');
      }
      runtime.dispose();
    } catch (e) {
      stdout.writeln('FAIL ${e.toString().split('\n').first}');
    }
  }

  stdout.writeln('\n--- summary ---');
  stdout.writeln('evaluated:      $evaluated / ${dart.length}');
  stdout.writeln('popular listed: $popular');
  stdout.writeln('detail+chapters:$detail');
  stdout.writeln('full chain:     $pages');
}
