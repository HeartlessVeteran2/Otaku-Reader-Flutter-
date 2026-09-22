/// Every persistence key in the app, as enum members grouped by domain.
///
/// `KvExtensions` (see `kv_helper.dart`) gives each member `.get<T>()`,
/// `.set<T>()` and `.delete()`, so a call site reads
/// `ReaderKeys.dualPageMode.set(2)` with no string anywhere.
library;

import 'package:otaku_reader/core/database/kv_helper.dart';

enum General {
  onboardingCompleted,
  lastOpenedTab,
  imageCacheThresholdGb,
  incognitoMode,
}

enum ThemeKeys {
  themeMode,
  isLightMode,
  isSystemMode,
  isOled,
  selectedVariantIndex,
  customColorIndex,
  customHexColor,
  useCoverColor,

  /// How round, how glowing and how blurred the chrome is — AnymeX's
  /// multipliers, so the whole app's shape is a setting rather than thirty
  /// hardcoded numbers. See `ChromeMetrics`.
  radiusScale,
  glowScale,
  blurScale,
}

enum ReaderKeys {
  readingLayout,
  readingDirection,
  webtoonDirection,
  dualPageMode,
  imageWidth,
  scrollSpeed,
  spacedPages,
  overscrollToChapter,
  preloadPages,
  showPageIndicator,
  cropBorders,
  fitToScreen,
  volumeKeysEnabled,
  invertVolumeKeys,
  autoScrollEnabled,
  autoScrollSpeed,
  customBrightnessEnabled,
  customBrightnessValue,
  colorFilterEnabled,
  colorFilterValue,
  colorFilterMode,
  grayscaleEnabled,
  invertColorsEnabled,
  readerTheme,
  keepScreenOn,
  alwaysShowChapterTransition,
  longPressPageActionsEnabled,
  autoWebtoonMode,
  displayRefreshEnabled,
  displayRefreshDurationMs,
  imageFilterQuality,
  tapZonesEnabled,
  tapZonesPaged,
  tapZonesContinuous,
  tapZonesMirrorReversed,
  tapZonesHaptics,
  panelModeEnabled,
  prefetchStrategy,
  prefetchOnWifiOnly,

  /// Which way up the reader is pinned, as a [ReaderOrientation] index.
  ///
  /// Appended, like every member above it: these are persisted by `index`, so
  /// inserting anywhere but the end re-points every stored value in place.
  orientationLock,

  /// Hide the status and navigation bars while a chapter is open.
  immersiveMode,

  /// Ask the platform to keep this window out of screenshots and the recents
  /// thumbnail.
  secureScreen,
}

/// What the reader falls back to for a key the user has never set.
///
/// Here rather than at either call site because there are two of them — the
/// reader reads the key, and the Settings switch renders it — and a pair that
/// disagrees puts a switch on screen showing the opposite of what the reader
/// does. Nothing would fail: each file is perfectly self-consistent on its own,
/// which is exactly the shape of defect this codebase keeps finding late.
abstract final class ReaderDefaults {
  /// A chapter is minutes of looking without touching the screen, so the
  /// display timeout fires mid-page. AnymeX defaults this on too.
  static const keepScreenOn = true;

  /// Off, as AnymeX's is. The reader's own controls carry the number one tap
  /// away, so a pill floating permanently over the artwork is something to ask
  /// for rather than something to find and turn off.
  static const showPageIndicator = false;

  /// Follow the device. Pinning a reader that the user never asked to pin is
  /// the kind of default that reads as the rotation lock being broken.
  static const orientationLock = 0;

  /// On. A chapter is the one screen in this app that *is* the content, and
  /// AnymeX's reader reaches the same place from the other side — it flips to
  /// `immersiveSticky` whenever the chrome hides.
  static const immersiveMode = true;

  /// Off. It costs a screenshot of your own reading, which is a normal thing
  /// to want, so it is asked for rather than found and turned off.
  static const secureScreen = false;

  /// Off, and the two e-ink keys are separate for the same reason the dim's
  /// magnitude and switch are: "zero means off" loses the setting every time
  /// it is toggled.
  static const displayRefresh = false;

  /// Long enough for a panel to settle on the slow displays this is for, and
  /// short enough not to read as a dropped frame on the fast ones.
  static const displayRefreshMs = 120;
}

enum LibraryKeys {
  gridSize,
  sortType,
  sortAscending,
  displayMode,
  showUnreadBadge,
  showDownloadBadge,
  lastCategoryId,
  hiddenCategoryIds,
}

enum SourceKeys {
  repoUrls,

  /// Per-repo last-refresh outcome, keyed by repo URL.
  ///
  /// Replaces a single global `lastRepoRefresh` timestamp, which was written on
  /// every refresh and read by nothing — one number for every repo cannot say
  /// *which* one is failing, which is the only question worth asking when you
  /// have several. Keys come from the enum member's `name`, so dropping the old
  /// member leaves an orphan row and breaks nothing.
  repoHealth,
  enabledLanguages,
  showNsfwSources,
  pinnedSourceIds,
}

enum DownloadKeys {
  downloadPath,
  concurrentDownloads,
  downloadOnWifiOnly,
  deleteAfterRead,
}

enum ServiceKeys { serviceType, homePageCards, homePageCardsMal }

enum UpdateKeys {
  updateInterval,
  updateOnWifiOnly,
  updateOnlyOngoing,
  lastUpdateCheck,
}

/// Per-media keys. The value is namespaced by an id, so one member covers every
/// manga without a schema or a migration: `stickySource_<mangaId>`.
enum DynamicKeys {
  stickySource,
  searchHistory,
  readerOverrides,
  trackBindings,
  deleteAfterReadOverride,
  autoDownloadOverride,

  /// Which AniList media a manga is, keyed by library row id.
  ///
  /// Deliberately separate from [anilistMeta]: the metadata is a disposable
  /// cache that a refetch overwrites wholesale, and a user's manual correction
  /// has to outlive it.
  anilistLink,

  /// The cached AniList payload, and when it was fetched.
  anilistMeta,
  anilistMetaAt;

  T get<T>(dynamic id, [T? defaultValue]) =>
      KvHelper.get<T>('${name}_$id', defaultVal: defaultValue);
  void set<T>(dynamic id, T value) => KvHelper.set<T>('${name}_$id', value);
  void delete(dynamic id) => KvHelper.remove('${name}_$id');
}
