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
