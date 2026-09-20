# Roadmap — AnymeX, manga-first, plus the add-ons

`FEATURES.md` is the **checklist** (what exists, what does not, what is
deliberately skipped). This is the **plan** — the order, and why that order.

---

## The target, in one sentence

**AnymeX's app, with the anime removed, the Tachiyomi catalogue added, and the
Kotlin Otaku-Reader's feature list folded in.**

Three sources, and each contributes something the other two do not:

| source | licence | contributes |
|---|---|---|
| **AnymeX** | MIT | the entire shape — chrome, information architecture, the AniList-rich surfaces, the settings depth. **Port its files; do not re-implement them.** |
| **Otaku-Reader (Kotlin)** | — | the add-ons: 79 shipped features AnymeX has no equivalent for — backup/restore, migration, downloads depth, library depth, security |
| **Komikku** | — | library/browse UX conventions |

Plus two things neither reference has: **Smart Panels** (panel detection), and
**per-repo health + source counts**, which already ship here.

---

## Where this actually is — measured, not estimated

```
this app        20,205 LOC   (+ 12,210 of tests)
AnymeX         199,965 LOC   total
  of which      35,672        lib/screens/anime      ← skipped
                 5,672        lib/screens/novel      ← skipped
                   919 + 3,467  watchium + its widgets ← skipped
```

So roughly **45k of AnymeX's 200k is anime/novel** and leaves with the
decision below. The manga-relevant remainder is still several times this
app's current size — most of it in `lib/widgets` (36k), `lib/controllers`
(21k) and `lib/utils` (20k), which is exactly the shared depth that makes
AnymeX feel finished and this app feel like a skeleton.

**That is the honest headline: the screens all exist here, and they are thin.**
The work is depth, not breadth.

### What is already at or ahead of parity

- **Extension repositories** — per-repo health and source counts; AnymeX has
  neither
- **Source runtime** — 55/55 Mangayomi Dart extensions evaluate, 6 complete
  `getPopular → getDetail → getPageList` live
- **AniList list editing** — all five score formats, read from the user's own
  account settings. The **read** asks for `score(format:)` and
  `Viewer { mediaListOptions { scoreFormat } }` in one request, so the number
  and its units cannot disagree, and adopts the live format into the cached
  viewer. The **write** then sends that adopted format. What remains is a
  seconds-wide window: change the format on another device between opening the
  editor and saving, and the write uses the format the read adopted. Closing
  it completely needs `scoreRaw`, which would mean inventing AniList's
  undocumented POINT_3 mapping — see `CLAUDE.md`.

### Corrected 2026-09-20 — reader settings are NOT at parity

The first version of this file claimed *"Reader settings — 34 keys against
AnymeX's 35"* and counted that as parity. Audited against the code, the reader
honours **two**: `readingLayout` and `readingDirection`. The other 32 keys are
declared and never read.

Worse, two Settings controls wrote a key nothing consumed — *Keep the screen
on* (no wakelock dependency existed in `pubspec.yaml`) and *Show the page
number* (no indicator existed in the reader). That is live UI wired to nothing,
which `CLAUDE.md` forbids, and it shipped.

**Both were fixed on 2026-09-20**, which takes the count to **four of 34**. The
30 that remain have no control behind them, so they are ordinary unbuilt
features rather than dead UI — see *Reader depth* below.

**The lesson, which is this project's oldest:** an enum of keys is a
declaration, not a behaviour. Counting declarations is how a checklist reports
parity for a feature nobody built. Tick what renders.

---

## Decisions already taken (2026-09-20)

Recorded so they stay visible and reversible, per the standing rule that
nothing is deferred without a line saying so.

| | decision |
|---|---|
| Anime/novel-only | **Skip** — calendar, video player settings, novel reader + its ~20 settings, torrent streaming (`libtorrent_flutter`, 12.3 MB/ABI), and the bridge's CloudStream / Sora / LnReader / Legado backends |
| Per-chapter comments | **Skip for now** — needs a hosted backend; that is infrastructure, not a screen |
| MangaUpdates layer | **Include** — next-chapter prediction, Recent News, Anime Adaptation |
| Kotatsu backend | **In scope** — it is a manga ecosystem |
| Build method | **Port AnymeX's files and adapt**, never re-implement from reading |

### What porting means in practice

Start from their file, keep a header pointing at its origin, and adapt these
six on the way in — CLAUDE.md's "Deliberate departures", which a straight copy
would drag in:

1. Flat `Get.put` DI with a load-bearing order → explicit `Bindings`
2. `Navigator.push(Get.context!, …)` thunks → the router
3. **`TlsSettings(verifyCertificates: false)` → never**
4. Auth tokens in the KV table → `flutter_secure_storage`
5. Unused declared deps (Hive, `background_downloader`, `jxl_coder`) → drop
6. `BaseService` returning `RxList<Widget>` → return data, let a screen render

---

## Phases

Each one ships on its own. Sizes are AnymeX's source, measured.

### Phase A — finish the shell *(in flight)*

**Done first: the two live controls that did nothing** — *Keep the screen on*
and *Show the page number*, each a shipped violation of this project's own
"never stub live UI" rule. Both ported from AnymeX: `wakelock_plus` behind a
`ScreenWakelock` seam, and `_buildPageInfo`'s pill.

**Done: the chrome conversion.** All seven remaining screens moved in one pass
— Settings, Accounts, Updates, Downloads, History, Home and Details — and
`lib/core/theme/one_ui.dart` is deleted, so the vocabulary is now one thing
rather than two. `test/one_ui_test.dart` was renamed to
`test/screen_chrome_test.dart` rather than removed: the sliver-slot hazard it
guards did not leave with the scaffold.

One deliberate exception, stated rather than assumed: **the Details screen
keeps its cover hero.** AnymeX's own details page has no pill header either —
`media_details_page.dart` builds an `AnymeXScaffold` with `showHeader` unset
and a `MediaHeader` as its first sliver — so replacing the hero with a pill
would move *away* from the reference, not toward it. What Details still owes
AnymeX is its three-tab shape (Info / Read / Comments), and that is a
redesign tracked with the AniList experience, not a chrome swap.

Still on the old shell: **Search and Browse**, which were never on
`OneUiScaffold` to begin with.

### Phase B — the catalogue

**The single biggest user-visible win, and it is not a UI change.** Mangayomi
tops out at 263 distinct sites; Tachiyomi/Mihon is **1,396 extension
packages**. Roughly 6× the catalogue and 10× the English-facing sources.

Adopt `anymex_extension_runtime_bridge` for **Aniyomi + Kotatsu**, alongside
the existing Mangayomi runtime (measured: the bridge is additive; `lib/source/`
runs on its pins with a one-line change, baseline held at 55/55 ÷ 6/6).

Known blockers, already measured:

| blocker | what it takes |
|---|---|
| `device_apps 2.2.0` — abandoned, `jcenter()`, dead under Gradle 9 | replace; two methods, Aniyomi-only |
| `install_plugin 2.1.0` — abandoned, no namespace | replace; one method |
| `libtorrent_flutter` rides along | ~33 MB across three ABIs for a torrent streamer a manga reader never opens |
| **LICENSE flips Apache-2.0 → GPLv3** | the bridge is GPLv3 + mandatory public source; accepted, personal build |

**This phase cannot be finished in the sandbox** — the Aniyomi path needs a
runtime-host APK verified on a device. Everything up to that point can land.

### Phase C — the AnymeX feel

The depth that separates "has the screens" from "is the app".

| | AnymeX source | size |
|---|---|---|
| Profile-led header on tab roots — AniList avatar + badge + greeting | `lib/widgets/header/header.dart` | 1,012 |
| ~~Radius / glow / blur **user multipliers** — roundness becomes a setting~~ | `multiplyRadius()` / `multiplyGlow()` | **shipped** |
| ~~In-row segmented selectors, replacing radio dialogs~~ | `anymex_tile.dart` | **shipped** |
| Searchable settings registry — relevance-scored, deep-links, highlights | `settings/search/*` | 659 |
| Tap-zones editor — four profiles | `settings_tap_zones.dart` | 544 |
| 5 missing reader settings | `readerControlTheme`, `chapterStyle`, `displayRefreshInterval`, `displayRefreshColor`, `navigateByNumber` | — |

The two struck rows landed together, because the second is a consumer of the
first. `ChromeMetrics` is a `ThemeExtension`, so every chrome widget reads the
multipliers off the theme it is already under through `context.radius()` /
`.glow()` / `.blur()` — rather than AnymeX's `Get.find`, which would make a
DI registration a precondition for laying out a card. `test/chrome_test.dart`
renders 35 chrome tests with no registrations at all, and that stays true.

A third multiplier was added beyond AnymeX's two: **blur**. The pill header is
this app's most expensive surface to composite, and a `BackdropFilter` at
sigma 0 still saves and composites a layer, so the widget drops the filter
entirely at zero rather than zeroing it — which makes the setting a real
performance control on a slow device, not only a taste one. The same applies
to the glow: at zero the whole `DecoratedBox` goes, because a `BoxShadow` with
no blur and no spread paints a hard rectangle rather than nothing.

`ChromeTile.choice` replaced the four radio dialogs (`_pick<T>`) on the
Settings screen, and `ChromeTile.slider` is what the three multiplier rows are
built from. Both are ports of `AnymeXTile`'s own factories.

### Phase D — the AniList experience

What "interconnected with AniList" was asked for, in full.

| | AnymeX source | size |
|---|---|---|
| Profile — header, stats tab, favourites, activity feed + replies + likes, social | `lib/screens/profile` | 13,042 |
| User stats | `lib/screens/stats` | 1,626 |
| Community + user recommendations | `lib/screens/community` | 1,431 |
| AI picks — paged recommendation cache | `lib/ai/animeo.dart` | 582 |
| Compatibility checker | `compatibility_result_page.dart` | 2,877 |
| Advanced search + `fetchFilterData` introspection | inside `search_view.dart` | 5,526 |
| MangaUpdates layer — prediction, news, adaptation | `lib/models/mangaupdates` | 3 models |
| SauceNAO reverse image search | `sauce_finder.dart` + view | — |

On MangaUpdates: build it AnymeX's way — a typed error
(`'MangaUpdates ID not found'`, `'Irregular release schedule'`) and the UI
**hides the tile** rather than rendering a failure. It scrapes two pages with
regexes and will rot; write that next to the code.

### Phase E — the add-ons

Otaku-Reader's 79 features, where AnymeX has no equivalent. Grouped by what
they need, not by the original issue numbers.

- **Data portability** — backup/restore (versioned JSON), Tachiyomi backup
  import, auto-backup scheduling, restore preflight
- **Migration** — the source-to-source wizard, plus the download-folder answer
  that has to ship with it
- **Trackers** — MAL, Kitsu, MangaUpdates, Shikimori beside AniList; batch
  sync; a tracking health page
- **Library depth** — FTS search, dynamic + hidden categories, saved
  filter/sort views, reading lists, duplicate detection, custom cover art,
  nav-tab reorder
- **Downloads depth** — smart rules, auto-download by category, queue manager,
  CBZ encryption, storage analytics, data-usage budget
- **Reader depth** — the 30 declared-but-unread `ReaderKeys` (crop borders,
  auto-webtoon, tap zones, colour filter and blend mode, e-ink refresh,
  auto-scroll, volume keys, long-press page actions, dual page, …), plus
  per-manga settings UI, presets, per-manga dynamic theme and read-time
  estimation. **This is a phase of its own, not a bullet** — the audit moved it
  here from "already at parity".
- **Security + system** — biometric app lock with scheduling, crash reporting,
  notification batching, home-screen widget, QR library sharing
- **Local source** — local manga folders (`lib/screens/local_source`, 2,359)

### Phase F — net-new

**Smart Panels.** Panel detection and auto-crop. Neither reference app has a
detector, so there is nothing to port and nothing to measure against. Last,
deliberately.

---

## How every slice is built

Non-negotiable, because each line is a defect this project has already shipped:

1. **Open AnymeX's version first.** Three recorded failures came from not
   doing this — a screen, a widget, and a 4,361-line subsystem.
2. **Port, then adapt.** Not read-then-rewrite.
3. **A rendered test per branch, at 320 / 360 / 384 *and* at a doubled system
   font.** `flutter analyze` is structurally blind to layout — eleven recorded
   instances. The doubled font caught a hollow guard that every width passed.
4. **Prove each guard by mutation.** Confirm the patch applied with `grep`,
   then read the `+P -F` counts, never the truncated failure list.
5. **Land a working slice, not a phase.** Two PRs were refused outright for
   exceeding a review bot's 150,000-character limit.
6. **Nothing is deferred without a line in `FEATURES.md` saying so and why.**

---

## The risks worth naming

- **Phase B ends at a device.** The Aniyomi runtime host cannot be verified in
  the sandbox. Everything else in that phase can land; that step waits.
- **Phase B costs the licence.** Linking the bridge makes the whole build
  GPLv3, regardless of how little of it is called. Accepted — personal build,
  not distributed.
- **Phase D's MangaUpdates features rot.** They scrape someone else's HTML.
  Ship them hiding on failure, and expect to fix them.
- **Scale.** The manga-relevant part of AnymeX is several times this app's
  current size. The screens exist; the depth does not. Phases C, D and E are
  each many slices, and that is the honest shape of the thing.
