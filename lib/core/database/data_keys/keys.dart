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
}

enum ReaderKeys {
  readingLayout,
  readingDirection,
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
  panelModeEnabled,
  prefetchStrategy,
  prefetchOnWifiOnly,
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
