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
