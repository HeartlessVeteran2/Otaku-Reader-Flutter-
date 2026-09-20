// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

/// The library URI that bridged types are registered under.
///
/// **This string is the extension-facing contract and must not be renamed to
/// match this package.** Every published Mangayomi source begins with
/// `import 'package:mangayomi/bridge_lib.dart';`, and the interpreter resolves
/// that import against the URI used at registration. Pointing it at
/// `package:otaku_reader/...` would leave every extension importing a library
/// that does not exist, and since `MProvider` is named in an `extends` clause,
/// each one would fail at class-definition time — the whole script, not one
/// method.
const String kBridgeLibraryUri = 'package:mangayomi/bridge_lib.dart';
