# Feature checklist

The scope, written down rather than remembered. Compiled from exhaustive sweeps
of the two reference apps — the Kotlin
[Otaku-Reader](https://github.com/HeartlessVeteran2/Otaku-Reader) (79 shipped
features by issue number) and [AnymeX](https://github.com/RyanYuuki/AnymeX) —
plus [Komikku](https://github.com/komikku-app/komikku) for library/browse UX.

`[x]` = shipped here. `[ ]` = not yet. `[~]` = partly, with the gap named.
**SKIP** = deliberately not doing, with the reason.

`ROADMAP.md` is the plan and the order. This file is the contract: **nothing is
deferred without a line here saying so and why.** That rule exists because the
deferrals used to live in task descriptions the developer never saw.

---

## How to read this, and why it was rewritten

This file read **3 ticked / 43 unticked** while phases 2-6 had in fact shipped,
so it could not be used to answer "what is missing" — which is exactly what it
is for. Rebuilt 2026-09-20 by auditing the code rather than by memory.

The audit corrected two things that had been stated as fact:

1. **Reader settings are not at parity.** `ReaderKeys` declares 34 keys, and it
   is tempting to read that as 34 features. The reader honours **two**:
   `readingLayout` and `readingDirection`. The rest are declared and unused.
2. **Two Settings controls did nothing.** "Keep the screen on" had no wakelock
   dependency or implementation anywhere in `lib/`, and "Show the page number"
   had no page indicator in the reader. Both wrote their key and were never
   read. That is live UI wired to nothing, which `CLAUDE.md` forbids, and it
   shipped. **Fixed 2026-09-20** — both are ticked below, and the reader now
   honours four keys rather than two.

A checklist that counts declarations rather than behaviour is how both got
missed. Tick what renders, not what compiles.

---

## Phase status

- [x] **0 — Skeleton.** Isar + recovery ladder, `KvHelper`, typed enum keys, M3 theming, `LazyIndexedStack` shell, explicit DI.
- [x] **1 — Source runtime.** Mangayomi Dart extensions via d4rt. 55/55 evaluate, 6 complete the full chain.
- [~] **2 — Browse, details, library, home.** Browse, global search, details with AniList carousels and the list editor all ship. Library is a grid with 4 sorts and a search box — no filters, categories, display modes or badges.
- [~] **3 — Reader.** Paged and webtoon, both directions, progress persistence and resume, keep-screen-on and a persistent page indicator. Four of ~40 reader settings are honoured.
- [~] **4 — Downloads, updates, history.** Queue with cancel/delete and storage usage; updates with mark-read and undo; history with search, remove, undo and resume. None of the depth below.
- [ ] **5 — Smart Prefetch, Smart Panels.** AniList metadata shipped; the other two have not started.
- [ ] **6 — Tracking fan-out, migration, stats, Komikku parity.**
- [ ] **7 — AniList profile, search, AI picks, compatibility.**

---

## Decisions — 2026-09-20

| | |
|---|---|
| **SKIP** — anime/novel-only | Calendar, video player settings, novel reader and its ~20 settings, torrent streaming (`libtorrent_flutter`, 12.3 MB/ABI), and the bridge's CloudStream / Sora / LnReader / Legado backends. This is a manga reader. |
| **SKIP for now** — per-chapter comments + moderation | AnymeX runs its own comments backend. Matching it means hosting one or depending on theirs; that is infrastructure, not a screen. Nothing else depends on it. |
| **INCLUDE** — MangaUpdates layer | Next-chapter prediction, Recent News, Anime Adaptation. Scrapes two pages with regexes and will rot — ship it AnymeX's way, hiding the tile on failure. |
| **IN SCOPE** — Kotatsu backend | A manga ecosystem. Bridge slice 2 had been narrowed to Aniyomi alone without that being said out loud. |
| **Build method** | Port AnymeX's files and adapt them; never re-implement from reading. See `ROADMAP.md` for the six departures a straight copy would drag in. |

---

## Reader

The single most important surface. Combined list from both apps.

> **Audited 2026-09-20.** The reader honoured `readingLayout` and
> `readingDirection` and nothing else, and two Settings controls — *Keep the
> screen on* and *Show the page number* — wrote a key the reader never read,
> so they were inert UI. **Both are now wired**, so `ReaderKeys` stands at 4
> honoured of 34; the other 30 have no control behind them and are ordinary
> unbuilt features rather than dead UI. `ReaderDefaults` holds the fallback for
> the two that have a switch, because the reader and the Settings row both need
> it and a disagreeing pair renders a switch showing the opposite of what the
> reader does.

**Modes & layout** — [x] paged and continuous · [~] 4 directions — **LTR and RTL only**; `ReadingDirection` has exactly two members, and top-down / bottom-up do not exist · [ ] dual-page (off/auto-landscape/force) with **shift double pages** · [ ] auto webtoon mode (switches to vertical from page aspect ratios) · [ ] fit-to-screen-width · [ ] webtoon side padding and page gap · [ ] image width multiplier + desktop max-width clamp · [ ] spaced pages

**Rendering** — [ ] tiled/subsampled decoding for tall strips (AnymeX's `subsampling_scale_image_view/` + FFI decoder) · [ ] crop borders (white/black margin removal) · [ ] image filter quality incl. Lanczos pre-scale · [ ] image quality / data-saver downscaling · [ ] pinch + double-tap zoom, disable-zoom-out option

**Navigation** — [ ] customisable tap zones, **four profiles** (paged/webtoon × horizontal/vertical) · [ ] navigation-mode presets (Default, L, Kindlish, Edge, Right-and-Left, Disabled) · [ ] invert tapping (none/horizontal/vertical/both) · [ ] volume keys + invert + **per-mode overrides** + hold-to-skip-5 · [ ] keyboard/DeX shortcuts · [ ] mouse wheel + trackpad · [ ] overscroll to prev/next chapter · [ ] **navigate by chapter number** (skips duplicate/scanlator dupes) · [ ] auto-scroll with speed, **pause-on-touch and auto-resume**

**Display** — [ ] custom brightness (AnymeX goes to −75) · [ ] colour filter with **RGBA sliders and 16 blend modes**, plus named presets · [ ] custom tint + opacity · [ ] greyscale · [ ] invert · [ ] reader background (9 options) · [ ] **e-ink flash** with duration/interval/colour · [x] keep screen on — `wakelock_plus`, taken when a chapter opens and released when it closes · [ ] fullscreen + cutout handling · [ ] orientation lock (7 modes) · [ ] secure screen (`FLAG_SECURE`)

**Chrome** — [ ] reader control theme registry (default/iOS) · [x] page indicator — a pill that stays on screen once the controls are hidden, off by default as AnymeX's is · [ ] page slider with haptic tick · [ ] **page thumbnail strip** (slider ⇄ filmstrip) · [ ] full-page gallery grid · [ ] in-reader chapter list with search + asc/desc + list/grid · [ ] chapter transition cards with **missing-chapter gap warning** · [ ] reading timer overlay · [ ] battery + clock overlay · [ ] zoom indicator

**Actions** — [ ] long-press page: save / share / copy URL / set as cover · [ ] page bookmark toggle · [ ] in-chapter download button · [ ] reader comments + chapter note · [ ] reader presets (save/apply/delete) · [ ] per-manga reader overrides + reset-to-global · [ ] incognito mode

**Exclusive to the Kotlin app** — [ ] Smart Prefetch (4 strategies, behaviour tracking, telemetry) · [ ] Smart Panels (**net-new: the Kotlin app has no detector**, only auto-crop + a UI shell) · [ ] SFX translator · [ ] OCR page translation · [ ] OCR text search across pages

---

## Library

> **Audited.** A cover grid, four sorts (title / last read / date added /
> unread) with asc-desc, and a search box. `CategoryEntry` exists in the schema
> and round-trips, but nothing in the UI creates, edits or filters by one.

[ ] Display modes (grid/comfortable/list/cover-only) + staggered · [ ] portrait/landscape column counts + **pinch to change columns** · [ ] badges (unread, downloaded, completed, NEW, type) · [ ] title on cover · [ ] category tabs with counts · [ ] grouping (category/source/status/tracker/none) · [~] **11 sorts** + asc/desc *(4 of 11: title, last read, date added, unread)* · [ ] **tri-state filters** (downloaded, unread, started, bookmarked, completed, tracking, dropped, source, reading list, genre, has-notes) · [ ] active-filter chips + clear all · [ ] **saved filter/sort views** · [ ] FTS search + advanced search (`author:` / `tag:` syntax) · [ ] greeting header · [ ] daily-goal card · [ ] continue-reading carousel · [ ] recommendations with dismiss · [ ] tablet two-pane detail panel

**Categories** — *(the Isar collection ships; no UI reaches it)* [ ] create/edit/delete/reorder · [ ] **hidden** (biometric-gated) · [ ] NSFW · [ ] locked · [ ] per-category update frequency · [ ] skip-updates toggle · [ ] **dynamic/smart categories** (11 rule types)

**Bulk actions** — [ ] select all / invert / deselect · [ ] mark read/unread · [ ] download · [ ] move category · [ ] remove **with undo** · [ ] notify toggle · [ ] mark completed/dropped · [ ] share · [ ] migrate · [ ] update selected · [ ] search globally · [ ] confirmation dialogs

**Maintenance** — [ ] refresh covers/metadata · [ ] reindex downloads · [ ] scan + delete orphaned files · [ ] **merge duplicates** + link alternative source + fill missing chapters · [ ] cross-source duplicate detection

**Reading lists** — [ ] create/edit/delete · [ ] export CSV/JSON

---

## Details

> **Audited.** Header with cover, title, author/artist, status and an
> expandable description all render, as do the AniList carousels (Characters,
> Related, Recommended) and the list editor. The chapter list sorts both ways,
> filters read/unread, multi-selects, and downloads or deletes per chapter.

[~] Header — cover, title, author/artist, status, expandable description and genre chips ship; the chips are **not** tappable, and there is no panorama toggle, stats row or **read-time estimate** · [ ] custom cover set/remove · [ ] **Edit Info** sheet writing `user*` override columns + reset-to-source · [ ] content type toggle (manga/manhwa) · [ ] cover theme override cycle · [ ] AI summary

[ ] Action row: library toggle, tracking, WebView, share, refresh · [ ] overflow: migrate, mark completed/dropped, download all/unread, open download folder, clear downloads, add to reading list, link to AniList, notify toggle, delete-after-read override · [ ] category picker on first favourite

**Chapter list** — [x] sort asc/desc · [ ] search · [~] filter sheet — read/unread only, no downloaded or **scanlator** · [ ] **scanlator pills** · [ ] **chapter range/chunk pills** · [ ] per-chapter progress + time estimate · [ ] thumbnail preview · [ ] note preview · [~] per-chapter menu — mark read/unread, download, delete; no mark-previous-read or **export CBZ** · [x] multi-select · [ ] continue-reading highlight · [ ] tile styles (compact/detailed/grid)

**Source binding** — [ ] source picker with search + type tabs + language sub-picker · [ ] **wrong-title remap**

---

## AniList (full AnymeX parity — see `CLAUDE.md` for the query set)

> **Audited.** Auth (PIN flow, token in `flutter_secure_storage`), the list
> editor in all five score formats, metadata with a 7-day cache, live progress
> sync on chapter finish, and three of the four carousels.

**Details Overview tab**, in order — [ ] quick actions (list status, custom list) · [ ] progress bar · [x] synopsis · [ ] stats grid (score, format, status, origin, chapters, popularity, source, studio) · [ ] alternative titles · [x] genres · [ ] **tags with rank %** · [ ] social "friends reading this" · [ ] seasons/prequel-sequel · [x] **characters carousel** · [x] **relations carousel** · [ ] **staff carousel** · [x] **recommendations carousel**

> AnymeX guards its Extras section with `if (controller.isAnime)`, so manga never
> gets **Recent News**, **Anime Adaptation** ("adapted from ch. X–Y") or
> **Next Release Prediction**. All three are written and MangaUpdates-backed.
> Ship them for manga — that is an improvement on AnymeX, not parity with it.

- [ ] Character / staff detail sheets (paged media lists)
- [x] **List entry editor**: status, score in **all five AniList formats** (POINT_100 / POINT_10_DECIMAL / POINT_10 / POINT_5 / POINT_3, read from the user's own account settings), progress, start/finish dates, private, delete. *(AniList's `repeat` and `notes` are net-new — AnymeX never touches them.)*
- [ ] Long-press **peek popup** for quick list editing
- [ ] Home: MANGA LIST / OTHER buttons, per-status carousels driven by `homePageCards`, **Recommended Manga excluding what you've already read**, community recommendations
- [ ] Profile: header, stats tab (genres/tags/staff, count/time/mean-score metrics), favourites, activity feed + replies + likes, social tab
- [ ] **Compatibility checker** (weighted heuristics; already has a full manga path)
- [ ] Advanced search + `fetchFilterData` introspection (genres, tags, formats, statuses, sources, chapter/volume ranges)
- [ ] AniList account settings mirror (title language, score format, section order, custom lists)
- [ ] List exporter (MAL-compatible XML)
- [ ] AI picks

---

## Downloads, updates, history

> **Audited.** Downloads: a queue with cancel and delete, all-or-nothing
> writes through a `.part` directory, and storage usage. Updates: library
> refresh, mark-read and undo. History: search, remove, undo and resume.
> Everything else below is absent.

[~] Queue with pause/resume/cancel/retry/move-to-front *(cancel only)* · [ ] **survives restart** (persisted queue) · [ ] foreground notification with progress · [ ] concurrency + chunk settings · [ ] download location picker · [ ] **CBZ export + AES-256 encryption** · [ ] auto-download new chapters + per-category include/exclude · [ ] download-ahead · [ ] **smart downloads** (trigger at % through a chapter, wifi/favourites/free-space gates) · [ ] delete-after-read + **keep-last-N** · [ ] data saver · [ ] storage analytics with per-entry delete · [ ] data usage dashboard + monthly budget

[x] Updates: list, mark read · [x] undo · [ ] group by manga/date · [ ] date filters · [ ] **to-be-updated sheet** · [ ] **last-run summary** (checked/new/skipped/failed) · [ ] multi-select · [ ] **update errors screen** (sticky headers, migrate-selected)

[x] History: search · [x] swipe-to-delete + undo · [x] resume · [ ] date-range filter · [ ] **date section headers** · [ ] multi-select

---

## Everything else

**Sources/extensions** — [x] repo management *(with per-repo health and source counts — AnymeX has neither)* · [x] install/update/uninstall from a repo index · [x] NSFW gate · [ ] auto-update · [ ] language filter · [ ] **pin + hide + categorise sources** · [ ] saved source searches · [ ] **persisted per-source filter state** · [ ] source health diagnostics · [ ] extension detail screen · [ ] **signer hash provenance** · [ ] blocklist · [ ] install from URL/file · [ ] Cloudflare WebView session bridge

**Tracking** — [~] AniList ships; MAL, Kitsu, MangaUpdates and Shikimori do not · [ ] **bind one manga to N trackers and fan out** · [ ] 95%-read threshold with **progress-regression guard** · [ ] per-tracker sync-on-read toggle · [ ] batch sync · [ ] tracking health page

**Backup/sync** — [ ] selective backup/restore with **pre-backup checklist and pre-restore preflight** · [ ] **AES-256-GCM encryption** · [ ] auto-backup schedule + retention · [ ] Tachiyomi/Mihon import · [ ] cloud backup (WebDAV) · [ ] cross-device progress sync · [ ] QR library share/scan

**Settings** — [ ] **settings search with deep-link and row highlight** · [~] theme — seed, Material You, custom, every variant and OLED all ship; no schedule · [x] **per-cover auto theme** · [ ] font family picker · [ ] **reorderable + hideable nav tabs** · [~] UI multipliers — glow, radius and blur ship as sliders on the Settings screen, read off a `ThemeExtension`; there is **no** animation-duration multiplier · [ ] card/carousel/navbar style registries · [ ] grain texture · [ ] liquid wallpaper · [ ] refresh-rate picker · [ ] advanced (user-agent override, DoH, verbose logging, clear cookies, battery optimisation, don't-kill-my-app) · [ ] storage manager with per-bucket sizes + auto-clear threshold · [ ] logs to file

**Security** — [ ] biometric app lock + **time/day schedule** · [ ] incognito · [ ] encrypted credential stores · [ ] certificate pinning · [ ] crash handler with copy-to-clipboard · [ ] opt-in crash reporting (user-supplied DSN)

**Other** — [ ] onboarding wizard · [ ] home-screen widgets + **configuration studio** · [ ] Discord RPC with **editable presence templates** · [ ] deep links + app shortcuts · [ ] share · [ ] statistics (streaks, heatmap, achievements, goals, **share card with anonymise toggle**) · [ ] **XP/rank tiers** · [ ] feed/discovery · [ ] migration wizard with **configurable flags incl. notes + custom cover** and range-select · [ ] local source (CBZ/ZIP/EPUB/folders, ComicInfo.xml) · [ ] OPDS (Komga/Kavita) · [ ] in-app updater with beta channel · [ ] **SauceNAO reverse image search** · [ ] notification batching + quiet hours + hide-content

---

## Deliberately not doing

- **Anime, video playback and the novel reader.** Manga-first, decided
  2026-09-20. Also out: the airing calendar, player settings, torrent
  streaming, and the bridge's CloudStream / Sora / LnReader / Legado backends.
- **Per-chapter comments and moderation**, for now — it needs a hosted
  backend. Recorded rather than dropped; nothing else depends on it.
- **Editing extensions or the test fixture** to make a source work. See
  `CLAUDE.md`.

### Reversed — this said the opposite, and was wrong

> *"A second source backend. Dart + JS covers the ecosystem; the APK backend
> exists in the Kotlin app only for catalogue size, which no longer applies."*

Measured: Mangayomi's ceiling is **263 distinct sites**, against Tachiyomi /
Mihon's **1,396 extension packages**. Catalogue size is not a footnote for a
manga reader — it is the product. A second backend, through AnymeX's bridge,
is now Phase B of `ROADMAP.md`. Kept visible because the old line was stated
with confidence and was the reason nobody looked.
