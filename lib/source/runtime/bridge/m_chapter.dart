// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:d4rt/d4rt.dart';
import 'package:otaku_reader/source/runtime/bridge/bridge_library.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';

class MChapterBridge {
  final mChapterBridgedClass = BridgedClass(
    nativeType: MChapter,
    name: 'MChapter',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return MChapter(
          name: namedArgs.get<String?>('name'),
          url: namedArgs.get<String?>('url'),
          dateUpload: namedArgs.get<String?>('dateUpload'),
          scanlator: namedArgs.get<String?>('scanlator'),
          isFiller: namedArgs.get<bool?>('isFiller'),
          thumbnailUrl: namedArgs.get<String?>('scanlator'),
          description: namedArgs.get<String?>('scanlator'),
          downloadSize: namedArgs.get<String?>('scanlator'),
          duration: namedArgs.get<String?>('scanlator'),
        );
      },
    },
    getters: {
      'name': (visitor, target) => (target as MChapter).name,
      'url': (visitor, target) => (target as MChapter).url,
      'dateUpload': (visitor, target) => (target as MChapter).dateUpload,
      'scanlator': (visitor, target) => (target as MChapter).scanlator,
      'isFiller': (visitor, target) => (target as MChapter).isFiller,
      'thumbnailUrl': (visitor, target) => (target as MChapter).thumbnailUrl,
      'description': (visitor, target) => (target as MChapter).description,
      'downloadSize': (visitor, target) => (target as MChapter).downloadSize,
      'duration': (visitor, target) => (target as MChapter).duration,
    },
    setters: {
      'name': (visitor, target, value) =>
          (target as MChapter).name = value as String?,
      'url': (visitor, target, value) =>
          (target as MChapter).url = value as String?,
      'dateUpload': (visitor, target, value) =>
          (target as MChapter).dateUpload = value as String?,
      'scanlator': (visitor, target, value) =>
          (target as MChapter).scanlator = value as String?,
      'isFiller': (visitor, target, value) =>
          (target as MChapter).isFiller = value as bool?,
      'thumbnailUrl': (visitor, target, value) =>
          (target as MChapter).thumbnailUrl = value as String?,
      'description': (visitor, target, value) =>
          (target as MChapter).description = value as String?,
      'downloadSize': (visitor, target, value) =>
          (target as MChapter).downloadSize = value as String?,
      'duration': (visitor, target, value) =>
          (target as MChapter).duration = value as String?,
    },
  );
  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mChapterBridgedClass, kBridgeLibraryUri);
  }
}
