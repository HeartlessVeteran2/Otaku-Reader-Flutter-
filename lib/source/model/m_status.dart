// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

/// Publication status, as Mangayomi's extensions report it.
///
/// The ordinal order is part of the extension contract — sources return the
/// index — so members must not be reordered.
enum Status {
  ongoing,
  completed,
  canceled,
  unknown,
  onHiatus,
  publishingFinished,
}

/// Kept because the extension index tags every entry with one, even though this
/// app only ever loads [ItemType.manga].
enum ItemType { manga, anime, novel }
