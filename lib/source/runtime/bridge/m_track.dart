import 'package:d4rt/d4rt.dart';
import 'package:otaku_reader/source/runtime/bridge/bridge_library.dart';
import 'package:otaku_reader/source/model/video.dart';

class MTrackBridge {
  final mTrackBridgedClass = BridgedClass(
    nativeType: Track,
    name: 'MTrack',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        return Track(
          file: namedArgs.get<String?>('file'),
          label: namedArgs.get<String?>('label'),
        );
      },
    },
    getters: {
      'file': (visitor, target) => (target as Track).file,
      'label': (visitor, target) => (target as Track).label,
    },
    setters: {
      'file': (visitor, target, value) =>
          (target as Track).file = value as String?,
      'label': (visitor, target, value) =>
          (target as Track).label = value as String?,
    },
  );
  void registerBridgedClasses(D4rt interpreter) {
    interpreter.registerBridgedClass(mTrackBridgedClass, kBridgeLibraryUri);
  }
}
