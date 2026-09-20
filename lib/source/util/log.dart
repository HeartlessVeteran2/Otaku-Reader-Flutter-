// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Logging for the extension runtime.
///
/// A misbehaving source is the most common support question this app will get,
/// so runtime failures are logged rather than swallowed — but only in debug, to
/// keep a third-party script from writing a user's URLs into a release log.
class Log {
  const Log._();

  static void info(String message) {
    if (kDebugMode) developer.log(message, name: 'source');
  }

  static void error(Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      developer.log('$error', name: 'source', error: error, stackTrace: stack);
    }
  }
}
