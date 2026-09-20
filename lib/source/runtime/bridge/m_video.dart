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
import 'package:otaku_reader/source/runtime/bridge/bridge_cast.dart';
import 'package:otaku_reader/source/model/video.dart';

class MVideoBridge {
  final mVideoBridgedClass = BridgedClass(
    nativeType: Video,
    name: 'MVideo',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return Video(
          positionalArgs.get<String?>(0) ?? '',
          positionalArgs.get<String?>(1) ?? '',
          positionalArgs.get<String?>(2) ?? '',
          headers: namedArgs.get<Map?>('headers')?.cast(),
          subtitles: namedArgs.get<List<Track>?>('subtitles'),
          audios: namedArgs.get<List<Track>?>('audios'),
        );
      },
    },
    getters: {
      'url': (visitor, target) => (target as Video).url,
      'quality': (visitor, target) => (target as Video).quality,
      'originalUrl': (visitor, target) => (target as Video).originalUrl,
      'headers': (visitor, target) => (target as Video).headers,
      'subtitles': (visitor, target) => (target as Video).subtitles,
      'audios': (visitor, target) => (target as Video).audios,
    },
    setters: {
      'url': (visitor, target, value) =>
          (target as Video).url = value as String,
      'quality': (visitor, target, value) =>
          (target as Video).quality = value as String,
      'originalUrl': (visitor, target, value) =>
          (target as Video).originalUrl = value as String,
      'headers': (visitor, target, value) => (target as Video).headers =
          asBridgedMap<String, String>(value, 'Video.headers'),
      'subtitles': (visitor, target, value) => (target as Video).subtitles =
          asBridgedList<Track>(value, 'Video.subtitles'),
      'audios': (visitor, target, value) => (target as Video).audios =
          asBridgedList<Track>(value, 'Video.audios'),
    },
  );
  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mVideoBridgedClass, kBridgeLibraryUri);
  }
}
