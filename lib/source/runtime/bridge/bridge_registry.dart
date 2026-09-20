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
import 'package:otaku_reader/source/runtime/bridge/document.dart';
import 'package:otaku_reader/source/runtime/bridge/element.dart';
import 'package:otaku_reader/source/runtime/bridge/filter.dart';
import 'package:otaku_reader/source/runtime/bridge/http.dart';
import 'package:otaku_reader/source/runtime/bridge/m_chapter.dart';
import 'package:otaku_reader/source/runtime/bridge/m_manga.dart';
import 'package:otaku_reader/source/runtime/bridge/m_pages.dart';
import 'package:otaku_reader/source/runtime/bridge/m_provider.dart';
import 'package:otaku_reader/source/runtime/bridge/m_source.dart';
import 'package:otaku_reader/source/runtime/bridge/m_status.dart';
import 'package:otaku_reader/source/runtime/bridge/m_track.dart';
import 'package:otaku_reader/source/runtime/bridge/m_video.dart';
import 'package:otaku_reader/source/runtime/bridge/source_preference.dart';

class BridgeRegistry {
  static void register(D4rt interpreter) {
    MDocumentBridge().registerBridgedClasses(interpreter);
    MElementBridge().registerBridgedClasses(interpreter);
    FilterBridge().registerBridgedClasses(interpreter);
    HttpBridge().registerBridgedClasses(interpreter);
    MMangaBridge().registerBridgedClasses(interpreter);
    MChapterBridge().registerBridgedClasses(interpreter);
    MPagesBridge().registerBridgedClasses(interpreter);
    MProviderBridged().registerBridgedClasses(interpreter);
    MSourceBridge().registerBridgedClasses(interpreter);
    MStatusBridge().registerBridgedEnum(interpreter);
    MTrackBridge().registerBridgedClasses(interpreter);
    MVideoBridge().registerBridgedClasses(interpreter);
    SourcePreferenceBridge().registerBridgedClasses(interpreter);
  }
}
