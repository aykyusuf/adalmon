# CLEAN-02 plan: CleanMyMac-style Temizlik section (read-only plan, 2026-11-12)

## Goal and constraints
Grow the CLEAN-01 cleaner (Süreçler > Temizlik) into a full Temizlik section covering the user's 8 final scope items (STATUS.md:230). The rules that bind the work:
- Battery: on-demand only, cancellable, `.utility` priority, no timers (STATUS.md:7).
- "mevcuttaki düzeni bozmamaya çok dikkat et" (STATUS.md:10): ⌘1–⌘9 and the existing tabs keep working.
- MIT repo: no GPL code. Rule lists may come only from MIT/Apache sources, with attribution.
- Trash is the default. Permanent delete is opt-in per operation, with double confirmation.
- Adalmon never runs admin commands.
- Never read TCC.db. Probe the real folder and re-probe on didBecomeActive.
- Tests use temp-dir fixture homes only.
- Agents never commit or install, and never touch real user folders.

## Verified facts this plan builds on
- `CleanupTrasher.validate` (Sources/App/Cleanup/CleanupTrasher.swift:76-120) accepts only items that are direct children of a catalog root, and the root must be under home (line 98, `isStrictDescendant(rootParts, of: homeParts)`). That rules out:
  - `/Applications` app bundles
  - deep `node_modules`/`.build` folders
  - files at any depth in user-chosen folders

  Phase 0 has to generalise it.
- `trashItem` happens in exactly one place (CleanupTrasher.swift:61). No file under Sources/App/Cleanup or Sources/App/Process calls `removeItem`/`unlink(`. It appears only in Agents, Saver and Wallpaper.
- `CleanupCategory` is a single shared enum (CleanupModel.swift:4). If every phase added cases there, every phase would touch the same file. Phase 0 removes that coupling.
- **Bug (verified):**
  - `.appCaches` skips only `cachesSkipNames` (FolderScanner.swift:160), the package-manager names, and the `com.apple.` prefix (CleanupModel.swift:106-112).
  - `blockedReason` matches the folder name against running bundle IDs (CleanupModel.swift:129).
  - `~/Library/Caches/Google`, `Firefox` and `Microsoft Edge` therefore never match a bundle ID. They are pre-selected (`defaultSelected` true) and can be trashed while the browser runs.
  - Phase 1 fixes this.
- Access: the probe only knows `.noAccess` and has no reason (CleanupScanner.swift:16-26). Nothing in Cleanup re-probes when the app becomes active. Other places use the didBecomeActive pattern, for example HistoryPage.swift:85.
- Navigation:
  - `MainSection.pages` holds 9 pages, and `shortcutKey = index+1` (MainSection.swift:8, 87-89). A 10th page would get the key "10", which is invalid.
  - The menu is built from `pages` (MainMenuBuilder.swift:68-73).
  - Tests pin ⌘1–⌘9: MainWindowPagesTests.swift:9-11, DockModeTests.swift:70-74, OfficeLogicTests.swift:347, BatteryPreviewTests.swift:152.
  - `ProcessesTab.cleanup` is referenced in ProcessesPage.swift:34 and ProcessesTabTests.swift:10-11.
  - `router.processesTab` is not persisted (SettingsRouter.swift:20), so removing the tab cannot break a saved state.
- Startup:
  - `StartupItemActions` already does disable/enable/remove of user LaunchAgents via launchctl and its own `FileTrashing` (StartupItemActions.swift).
  - Background/login items are read-only from `sfltool dumpbtm` (BackgroundItemScanner.swift:6).
- The app is not sandboxed: Adalmon.entitlements has no app-sandbox key, and it has apple-events.
- project.yml globs `Sources/App` and `Tests` (project.yml:24-25, 207-208), so new files need no project.yml edit. Only `xcodegen generate` is needed.

## Placement (recommendation; the user decides, see Q1)
- Add a new page `MainSection.cleanup` ("Temizlik", `sparkles`) **appended after Ajan ofisi**, with the shortcut **⌘0**.
- ⌘1–⌘9 stay unchanged. `shortcutKey` maps index 9 to "0".
- The page uses a `CapsuleTabBar`-style sub-section bar. The sections are:
  - Akıllı tarama
  - Sistem çöpü
  - Geliştirici
  - Kaldırıcı
  - Büyük & eski
  - Kopyalar
  - Gizlilik
  - Yer kaplayanlar
  - Başlangıç
  - Bakım
- Süreçler > Temizlik tab: removed, and its job moves to the new page (Q2).
- Başlangıç stays in Süreçler. The Temizlik > Başlangıç sub-section embeds the **same** `StartupItemsView` (one model, one view).

## Parallel-work rules (for every implementer brief)
- One shared working tree. Every agent keeps the tree compiling after each step: no half-written files left across a build.
- Only the main session runs `xcodegen generate` and the full test suite. Agents build and test their own test class with `-only-testing`.
- Each agent uses its own DerivedData at `-derivedDataPath /private/tmp/claude-501/adalmon-dd-<phase>` and deletes it afterwards. The disk is about 96% full (STATUS.md:12).
- Never run two xcodebuilds on the same DerivedData (STATUS (f)).
- Optional: detached git worktrees (no branch) per agent. This is only on the user's say-so (Q6).
- Order:
  1. Phase 0 and Phase N (navigation shell) run in parallel. Their files do not overlap.
  2. Then Phases 1–6 in parallel.
  3. Then Phase 7 (Akıllı tarama).

## Shared conventions (defined in Phase 0, used by all)
- `CleanupKind`: a string-backed `struct` ID (`"junk.appCaches"`, `"dev.nodeModules"`, `"apps.bundle"`...). It replaces the need to extend one enum. The existing `CleanupCategory` keeps working: Phase 0 adds `var kind: CleanupKind`.
- `DeletionCandidate`: path, dev, ino, bytes, kind, scope, `blockingBundleIDs: Set<String>` (apps that must not be running), `displayName`.
- `DeletionScope` (the policy):
  - `.directChild(roots: [String])`: existing behaviour. Each root must be under home.
  - `.descendant(roots: [String], nameAllowlist: Set<String>?)`: user-chosen roots. Each root must be under home or on an external volume, and must not be a protected path itself. Example: `node_modules` and `.build` with an allowlist of names, or large/duplicate files with no allowlist.
  - `.appBundle`: the parent must be exactly `/Applications`, `/Applications/<one subfolder>` or `~/Applications`. The extension must be `.app`. Never anything under `/System`, and never `com.apple.*`.
  - `.exactFile(allowed: Set<String>)`: browser history/cookie files and preference plists, matched by exact canonical path.
- Checks common to every scope, in `CleanupDeleter`:
  - absolute, clean path
  - lstat, not a symlink, dev/ino unchanged since the scan
  - realpath of the parent
  - the protected-path list (existing, plus `/System`, `/Library`, `/usr`, `/bin`, `/sbin`, `/private`, `/opt/homebrew` root itself, `~/Library` root folders, the user-chosen roots themselves)
  - no blocking bundle ID running (re-read **at delete time**)
  - not Adalmon's own bundle or support directory
- Each phase ships its own `*Rules.swift` that produces `DeletionCandidate`s. The deleter never needs editing again.

---

## Phase 0: access flow + single guarded deleter (size M)
**Owns:**
- `Sources/App/Cleanup/CleanupTrasher.swift`: rename to `CleanupDeleter.swift`. Keep a `typealias CleanupTrasher = CleanupDeleter` only if needed.
- new `Sources/App/Cleanup/Core/DeletionPolicy.swift`
- new `Sources/App/Cleanup/Core/CleanupAccess.swift`
- new `Sources/App/Cleanup/Core/CleanupAuditLog.swift`
- `Sources/App/Cleanup/CleanupScanner.swift`: only `probe` gets an injectable `PathProbe` and returns a reason.
- `Sources/App/UI/MainWindow/Processes/CleanupCategoryCard.swift`
- `Sources/App/UI/MainWindow/Processes/CleanupView.swift`: access banner and delete-mode wiring only.
- new `Sources/App/UI/MainWindow/Cleanup/Shared/AccessHelpSheet.swift`
- new `Sources/App/UI/MainWindow/Cleanup/Shared/DeleteConfirmation.swift`
- `Tests/CleanupTests.swift` (adapt)
- new `Tests/CleanupDeleterTests.swift`
- new `Tests/CleanupAccessTests.swift`

**Data model:**
- `DeleteMode { trash, permanent }`
- `DeletionCandidate`, `DeletionScope`, `CleanupKind` (above)
- `AccessReason`:
  - `.filesAndFolders(folder)` for Downloads, Desktop and Documents
  - `.fullDiskAccess` for `.Trash`, MobileSync, `~/Library/Safari`, Mail, Messages
  - `.appData` for `~/Library/Containers/<other app>` and Group Containers. Assumption: on recent macOS this raises the "access data from other apps" prompt.
  - `.appManagement` for deleting other apps' bundles. Assumption.
  - `.systemProtected`: SIP. No button is shown.
- `CleanupAccess.reason(for path:home:)` is a pure table. Each reason has a deep link:
  - `Privacy_FilesAndFolders`
  - `Privacy_AllFiles`
  - `Privacy_AppBundles` (assumption, must be verified live)

**Work:**
1. `CleanupDeleter.delete(_ candidates:, mode:) -> [CleanupResult]`. It validates each candidate per its scope plus the common checks.
   - `.trash` uses `FileManager.trashItem`.
   - `.permanent` uses `FileManager.removeItem`, **only** after a second dev/ino recheck right before the call.
   - `removeItem` lives in this one file only.
   - Each delete closure is injectable for tests.
2. Audit log `Cleanup-log.jsonl`. Add `mode` and `kind` fields. `readLog` defaults a missing `mode` to `"trash"`, so old lines still parse. Keep the 500-line cap.
3. `DeleteConfirmation` sheet:
   - Step 1 shows the summary: count, size, mode, and "Çöp'ten geri alınabilir" or "GERİ ALINAMAZ".
   - Permanent adds step 2: a red, destructive second dialog with the count and size repeated, plus a checkbox "Kalıcı olarak silineceğini anlıyorum". Return is not the default key.
   - The mode resets to Trash after every operation. It is never persisted (Q3).
4. Access flow:
   - Per-root reason text and the matching button. Help sheet: 3 steps + "+ ile Adalmon'u ekle" + "Tekrar dene".
   - Auto re-probe on `NSApplication.didBecomeActiveNotification`, **only while some root is `.noAccess`**. The observer is removed after that. No timers.
   - If it is still denied after returning from Settings, offer "Adalmon'u yeniden başlat".
   - Show a "Tam Disk Erişimi: açık/kapalı" badge from a canary probe of `~/Library/Safari` (assumption: EPERM without FDA, no prompt).
   - Never open TCC.db.
5. The existing CleanupView uses the new deleter and the mode toggle. Behaviour is otherwise unchanged.

**Safety:**
- Scopes as above.
- A symlink anywhere in the item path is caught by the realpath-of-parent plus lstat-of-leaf check.
- `.descendant` refuses an item that equals a chosen root.
- The `.appBundle` path list is fixed.

**Tests** (fixture home in `FileManager.default.temporaryDirectory`; fake trash/remove closures):
- every scope accept/refuse case
- dev/ino swap between scan and delete for both modes
- a permanent delete actually removes the item, inside the fixture only
- log migration of a line without `mode`
- the access reason table
- re-probe moves `.noAccess` to `.scanned` with an injected probe

**Done when:**
- `xcodebuild test ... -only-testing:AdalmonTests/CleanupTests -only-testing:AdalmonTests/CleanupDeleterTests -only-testing:AdalmonTests/CleanupAccessTests` exits 0.
- `grep -rln "removeItem\|unlink(" Sources/App/Cleanup Sources/App/UI/MainWindow/Cleanup Sources/App/UI/MainWindow/Processes` prints only `Sources/App/Cleanup/CleanupDeleter.swift`.
- `grep -rn "TCC.db" Sources` prints nothing.
- The diff touches only the files listed above.

## Phase N: navigation shell (size S; parallel with Phase 0)
**Owns:**
- `Sources/App/UI/MainWindow/MainSection.swift`
- `Sources/App/UI/MainWindow/MainWindowDetail.swift`
- `Sources/App/UI/MainWindow/Processes/ProcessesTab.swift`
- `Sources/App/UI/MainWindow/Processes/ProcessesPage.swift`
- new `Sources/App/UI/MainWindow/Cleanup/CleanupPage.swift`
- new `Sources/App/UI/MainWindow/Cleanup/CleanupSubsection.swift` (enum + titles + icons)
- **stub files**, one per later phase, each containing a placeholder view. Ownership passes to the phase named in brackets:
  - `CleanupJunkSection.swift` [P1]: embeds the existing `CleanupView()` for now.
  - `CleanupDevSection.swift` [P1]
  - `UninstallerSection.swift` [P2]
  - `LargeOldSection.swift` [P3]
  - `DuplicatesSection.swift` [P3]
  - `PrivacySection.swift` [P4]
  - `SpaceLensSection.swift` [P5]
  - `CleanupStartupSection.swift` [P6]: embeds `StartupItemsView()`.
  - `MaintenanceSection.swift` [P6]
  - `SmartScanSection.swift` [P7]
- Tests: `MainWindowPagesTests.swift`, `DockModeTests.swift`, `ProcessesTabTests.swift`
- `SettingsRouter.swift`: add `cleanupSubsection` only.

**Work:**
- Append `.cleanup` to `pages`. Set `shortcutKey` so index 9 returns "0".
- Update the pinned test arrays to 10 entries, ending in "0". DockModeTests' `[5]`/`[6]` asserts stay valid.
- Remove `ProcessesTab.cleanup`. ProcessesTabTests' `disk.neighbor(1)` becomes `.disk`.
- `AdalmonRoute` lives in WidgetShared and is also compiled into the widget. **Not touched** in this plan: an `adalmon://cleanup` route is optional, later.

**Done when:**
- `-only-testing:` MainWindowPagesTests, DockModeTests, ProcessesTabTests, MainWindowPreviewTests, OfficeLogicTests and BatteryPreviewTests exit 0.
- `grep -rn "\.cleanup" Sources/App/UI/MainWindow/Processes` prints nothing.

---

## Phase 1: system junk + developer (size L)
**Owns:**
- `Sources/App/Cleanup/CleanupModel.swift`
- the rest of `Sources/App/Cleanup/CleanupScanner.swift` (after Phase 0)
- new `Sources/App/Cleanup/Junk/JunkRules.swift` (logs, browser caches, mail downloads list-only)
- new `Sources/App/Cleanup/Junk/DevRules.swift`
- new `Sources/App/Cleanup/Junk/ProjectArtifactScanner.swift`
- new `Sources/App/Cleanup/Junk/ToolCommands.swift`
- `CleanupView.swift` and `CleanupCategoryCard.swift` (moved under the Cleanup UI folder, or kept in place)
- stubs `CleanupJunkSection.swift` and `CleanupDevSection.swift`
- new `Tests/JunkRulesTests.swift`
- new `Tests/DevArtifactTests.swift`

**Categories:**
- Logs: `~/Library/Logs/*` direct children, excluding `DiagnosticReports`. List only, default off.
- **Browser caches (fixes the bug):**
  - New kinds with a folder-to-bundle map:
    - `Caches/Google/Chrome` and `Caches/com.google.Chrome` → `com.google.Chrome`
    - `Caches/Firefox` and `Caches/org.mozilla.firefox` → `org.mozilla.firefox`
    - `Caches/Microsoft Edge` and `Caches/com.microsoft.edgemac` → `com.microsoft.edgemac`
  - These folders are removed from `.appCaches`: add them to the skip list.
  - `blockingBundleIDs` is checked at scan **and** at delete time.
  - If the browser is running, the card says "Önce tarayıcıyı kapatın".
- Developer, global:
  - Gradle `~/.gradle/caches`
  - Cargo `~/.cargo/registry/cache` and `/src` (not `bin`)
  - CocoaPods `~/Library/Caches/CocoaPods`
  - Docker: **only** `~/Library/Containers/com.docker.docker/.../Docker.raw` is NEVER offered. Docker space goes through the tool command (below).
- Project artifacts:
  - The user picks project folders with NSOpenPanel; the paths are stored in prefs.
  - `ProjectArtifactScanner` walks them for `node_modules`, `.build`, `DerivedData`, `target` (only if `Cargo.toml` is a sibling), `Pods` (only if `Podfile` is a sibling), and `build` (only if `build.gradle*` is a sibling).
  - It does not descend into a found artifact, and it skips hidden directories other than `.build`.
  - It respects a depth cap of 6 and skips symlinks.
  - Scope: `.descendant(roots: chosen, nameAllowlist: [those names])`.
  - Optional: "son değişiklik > 30 gün" filter.
- Tool commands (Q4): `brew cleanup` (`brew cleanup -n` preview), `docker system df` plus `docker builder prune`.
  - Run as the user via the existing `CommandRunner`, with a timeout, never sudo.
  - Shown as "kalıcı; aracın kendi komutu" with a single confirm.
  - Disabled if the binary is missing.

**Battery:** each scan is a `Task.detached(priority: .utility)` with `Task.isCancelled` checks per directory. The project walk reports progress.

**Tests:**
- fixture home with fake Chrome/Firefox/Edge cache dirs; running set → blocked at delete
- project tree with `node_modules` nested in `node_modules` (only the outer one listed)
- `target` without `Cargo.toml` is not listed
- symlinked project root is refused
- ToolCommands with a fake runner (no real brew or docker)

**Done when:**
- `-only-testing:` JunkRulesTests, DevArtifactTests and CleanupTests exit 0.
- `grep -n "\"Google\"\|Microsoft Edge\|Firefox" Sources/App/Cleanup/CleanupModel.swift` shows them in the skip list.

## Phase 2: uninstaller + orphans (size L)
**Owns:**
- new `Sources/App/Cleanup/Apps/InstalledAppScanner.swift`
- new `Sources/App/Cleanup/Apps/LeftoverRules.swift`
- new `Sources/App/Cleanup/Apps/OrphanFinder.swift`
- stub `UninstallerSection.swift`
- new `Sources/App/UI/MainWindow/Cleanup/Apps/AppLeftoverList.swift`
- new `Tests/UninstallerTests.swift`

**Model:** `InstalledApp`:
- url, bundleID, name, version, bytes, isAppStore (`_MASReceipt`), ownerIsRoot, running
- `leftovers: [DeletionCandidate]`

**Rules:**
- Enumerate `/Applications` (plus one level of subfolders) and `~/Applications`. Skip:
  - `com.apple.*`
  - Adalmon itself
  - apps in `/System`
- Leftover locations are matched by **exact** bundle ID, or by exact app name for folders that are named by app:
  - `~/Library/Application Support/<id|name>`
  - `Caches/<id>`
  - `Preferences/<id>.plist` and `Preferences/ByHost/<id>.*.plist`
  - `Saved Application State/<id>.savedState`
  - `HTTPStorages/<id>`
  - `WebKit/<id>`
  - `Logs/<name>`
  - `Cookies/<id>.binarycookies`
  - `LaunchAgents/<id>*.plist`
  - `Application Scripts/<id>`
  - `Containers/<id>` (appData access)
  - `Group Containers/*.<id>` (exact suffix)
- No fuzzy matching.
- **Orphans:** the same locations. An entry qualifies when:
  - the name is reverse-DNS-shaped
  - it is not `com.apple.*`
  - `NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil
  - it is not in the installed list

  Orphans are listed with **default unselected** and a ≥1 MB filter for folders.

**Safety:**
- The app must not be running; check again at delete time.
- Root-owned and App Store apps are not deletable without admin. They get "Finder'da göster", with a note that Finder will ask for the password.
- `trashItem` failing with a permission error maps to `AccessReason.appManagement`.
- Preferences plists use `.exactFile`.
- The bundle uses `.appBundle`.
- The LaunchAgent plist goes through the existing `StartupItemActions.remove`, which does bootout first.

**Tests:**
- fixture `Applications/` with fake `.app` bundles (Info.plist only), plus a fixture Library
- exact-match leftovers only, so `com.foo.Bar2` is not matched for `com.foo.Bar`
- orphan detection with an injected resolver
- running app is refused
- `/System/Applications/X.app` and symlinked `.app` are refused

**Done when:** `-only-testing:AdalmonTests/UninstallerTests` exits 0.

## Phase 3: large/old + duplicates (size M)
**Owns:**
- new `Sources/App/Cleanup/Files/LargeOldScanner.swift`
- new `Sources/App/Cleanup/Files/DuplicateFinder.swift`
- new `Sources/App/Cleanup/Files/FileRootsStore.swift` (chosen folders; default Downloads, Documents, Desktop)
- stubs `LargeOldSection.swift` and `DuplicatesSection.swift`
- new `Tests/LargeOldTests.swift`
- new `Tests/DuplicateFinderTests.swift`

**Rules:**
- Size is computed from `st_blocks`.
- **Skip dataless/iCloud-evicted files** (`st_flags & SF_DATALESS`), so nothing gets downloaded.
- Skip package contents: `.app`, `.photoslibrary`, `.musiclibrary`, `.fcpbundle`, and `.git` directories.
- Thresholds: large ≥ 100 MB, old ≥ 1 year (adjustable).
- Duplicates:
  1. group by size (≥ 1 MB)
  2. hash the first 64 KB with SHA256 (CryptoKit, Apple)
  3. full SHA256 only for groups that still match, streamed in 1 MB chunks
- Keep one file per group, auto-chosen as the oldest or the shortest path; the user can change it. Never pre-select all copies.
- Note in the UI that APFS clones may free about 0 bytes.
- Scope: `.descendant(roots: chosen)`.

**Battery:** utility priority, cancellable between files, progress shown, no scan without a click.

**Tests:**
- fixture files with equal sizes but different content
- identical content → one group
- symlink not followed
- hardlink counted once
- dataless flag, simulated through an injected stat closure
- cancellation

**Done when:** `-only-testing:` LargeOldTests and DuplicateFinderTests exit 0.

## Phase 4: browser privacy (size M)
**Owns:**
- new `Sources/App/Cleanup/Privacy/BrowserPrivacyRules.swift`
- stub `PrivacySection.swift`
- new `Tests/BrowserPrivacyTests.swift`

**Rules (`.exactFile`; the browser must be closed, checked at scan and at delete):**
- Chrome/Edge per profile: `History`, `History-journal`, `Cookies`, `Cookies-journal`, `Visited Links`, `Top Sites`. **Never** `Bookmarks`, `Login Data` or `Preferences`.
- Firefox: `cookies.sqlite` (+ `-wal`, `-shm`), `formhistory.sqlite`. **Not `places.sqlite`**, because it holds the bookmarks (Q5).
- Safari: `~/Library/Safari/History.db*` (FDA) and `~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies` (assumption on the path). If the folder is unreadable, the access flow shows `.fullDiskAccess`.
- Confirmation text lists exactly what the user will lose: log-outs from all sites, and history.

**Tests:**
- fixture profile directories
- `Bookmarks`, `Login Data` and `places.sqlite` are never produced
- running browser is refused

**Done when:**
- `-only-testing:AdalmonTests/BrowserPrivacyTests` exits 0.
- `grep -n "places.sqlite\|Login Data\|Bookmarks" Sources/App/Cleanup/Privacy/BrowserPrivacyRules.swift` shows them only in a deny list.

## Phase 5: Yer kaplayanlar (treemap) (size M)
**Owns:**
- new `Sources/App/Cleanup/SpaceLens/TreemapLayout.swift` (own squarified algorithm, pure)
- new `Sources/App/Cleanup/SpaceLens/SpaceLensModel.swift`
- stub `SpaceLensSection.swift`
- new `Sources/App/UI/MainWindow/Cleanup/SpaceLens/TreemapCanvas.swift`
- new `Tests/TreemapLayoutTests.swift`

**Work:**
- On click, scan the chosen root (default: home) with the existing `FolderScanner` at `maxDepth: 1`. Drill-down rescans one level.
- Draw with a SwiftUI `Canvas`. No animation loop.
- Actions: "Finder'da göster", and "Büyük & eski'ye ekle" (hands off to the Phase 3 list).
- **Read-only:** no delete from the treemap.
- Skip TCC folders, which show the access banner instead.

**Tests:**
- layout areas proportional to input within 1%
- no overlap, everything within bounds
- zero and one-item inputs

**Done when:** `-only-testing:AdalmonTests/TreemapLayoutTests` exits 0.

## Phase 6: Başlangıç extension + Bakım info (size M)
**Owns:**
- `Sources/App/Process/StartupItem*.swift` and `Sources/App/Process/BackgroundItem*.swift` (extend)
- `Sources/App/UI/MainWindow/Processes/StartupItemsView.swift`, `StartupItemRow.swift`, `StartupItemsModel.swift`, `BackgroundItemRow.swift`
- stubs `CleanupStartupSection.swift` and `MaintenanceSection.swift`
- new `Sources/App/Cleanup/Maintenance/MaintenanceInfo.swift`
- `Tests/StartupItemTests.swift`
- new `Tests/MaintenanceInfoTests.swift`

**Startup extension (no admin):**
- Flag **broken** agents, where the plist's `Program`/`ProgramArguments[0]` does not exist. These get a "Kaldır" button (user scope only, via the existing `remove`).
- Show the developer and signing information already parsed from `sfltool`.
- Global `/Library/LaunchAgents` and `/Library/LaunchDaemons`: read-only, with a copyable `sudo launchctl ...` command.
- Login items (BTM): there is no supported toggle API for other apps. Offer the "Giriş Öğeleri'ni aç" deep link.
- Optional: legacy login items via System Events AppleScript. This raises the Automation prompt, so it comes after a user click only.

**Bakım (info + copy only, never executed):**
- local TM snapshots: `tmutil listlocalsnapshots /`. Read-only, and it may need no admin (assumption). Copy `tmutil thinlocalsnapshots / ...`.
- DNS flush command
- the `purge` explanation ("diski boşaltmaz")
- the Spotlight reindex warning (heavy on battery)

**Tests:**
- broken-agent detection on fixture plists
- MaintenanceInfo produces commands but has no runner dependency
- `grep -rn "sudo" Sources/App/Cleanup/Maintenance` finds them only in string literals

**Done when:**
- `-only-testing:` StartupItemTests and MaintenanceInfoTests exit 0.
- `grep -rn "CommandRunner.run\|Process()" Sources/App/Cleanup/Maintenance` prints nothing.

## Phase 7: Akıllı tarama overview (size S, last)
**Owns:**
- stub `SmartScanSection.swift`
- new `Sources/App/Cleanup/SmartScan/SmartScanAggregator.swift` (the only file that lists every phase's rules)
- new `Tests/SmartScanTests.swift`

**Work:**
- One click runs only the **safe default** kinds in sequence, at utility priority and cancellable: app caches, browser caches (closed browsers only), dev global caches, and the Trash size.
- It shows per-section totals with "İncele" links to the sub-sections.
- Nothing risky is pre-selected: orphans, large files, duplicates, privacy and project artifacts only show counts.
- "Temizle" goes through `DeleteConfirmation` with Trash mode.

**Tests:**
- the aggregator over a fixture home
- cancellation stops subsequent kinds

**Done when:**
- `-only-testing:AdalmonTests/SmartScanTests` exits 0.
- The full suite passes, apart from the known flakies (STATUS: PanelControllerTests, SessionProcessSampler, OfficeLiveArrival, BatteryLiquidGlyphTests on battery).
- Then the user signs off.

---

## Risks and assumptions
- **Verified:**
  - the browser cache bug
  - the direct-child-under-home validator limit
  - the ⌘1–⌘9 test pins
  - `processesTab` is not persisted
  - no sandbox
- **Assumptions (unverified):**
  - deep link `Privacy_AppBundles` for App Management
  - `~/Library/Containers/<other id>` prompts on recent macOS
  - `~/Library/Safari` canary returns EPERM without FDA and without a prompt
  - NSOpenPanel selection grants folder TCC to a non-sandboxed app
  - `tmutil listlocalsnapshots` works without admin
  - Safari cookie path
  - FDA grants drop on re-signed debug builds
- Permanent delete is irreversible. That is why there are two confirmations, the mode resets every time, the audit log records it, and dev/ino is rechecked just before deletion.
- `brew cleanup` and Docker prune are permanent by nature and bypass the deleter (Q4).
- Rule lists: if any list is taken from mac-cleanup-go (MIT) or mac-cleanup-py (Apache-2.0), add it to Ayarlar > Lisanslar. Copy nothing from Mole, Pearcleaner, dupeGuru or Objective-See.
- Parallel agents in one tree: see the rules above.

## Done when (whole task)
- Every phase's `-only-testing` command exits 0.
- The full suite passes, apart from the known flakies.
- `grep -rln "removeItem" Sources/App/Cleanup Sources/App/UI/MainWindow/Cleanup` prints only `Sources/App/Cleanup/CleanupDeleter.swift`.
- `grep -rn "TCC.db\|sudo " Sources/App --include=*.swift` matches only string literals in Maintenance/Startup copy texts.
- The live check passes: Downloads with "Erişim yok" leads to Settings, back to Adalmon, and an automatic re-scan.
- The user signs off (tasks.json `done_when`).

## Questions for the user (options; recommended first)
1. **Placement:**
   - (a) **Recommended:** a new sidebar page "Temizlik", appended after Ajan ofisi, ⌘0. ⌘1–⌘9 stay the same.
   - (b) Insert it after Süreçler as ⌘7. Pil, Duvar kâğıdı and Ajan ofisi shift. This changes the layout the user knows.
   - (c) Keep it as a tab inside Süreçler. That is very cramped for 10 sub-sections.
2. **Süreçler > Temizlik tab:**
   - (a) **Recommended:** remove it, so everything lives in the new page. Başlangıç stays in Süreçler too.
   - (b) Keep it as a shortcut button "Temizlik sayfasını aç".
3. **Permanent-delete toggle:**
   - (a) **Recommended:** per operation in the confirm sheet; it resets to Trash every time.
   - (b) A persistent setting in Ayarlar. Riskier, because people forget it is on.
4. **brew/Docker:**
   - (a) **Recommended:** run the tool's own command (as the user, no sudo) after a dry-run preview, clearly labelled "kalıcı".
   - (b) Info plus a copyable command only, like the admin items.
5. **Firefox history:**
   - (a) **Recommended:** skip it. `places.sqlite` also holds the bookmarks. Cookies and form history only.
   - (b) Delete the history rows via SQLite. Schema risk.
6. **Parallel agents:**
   - (a) **Recommended:** one shared tree with the build rules above.
   - (b) Detached git worktrees without a branch, one per agent. Cleaner builds, more disk on a disk that is about 96% full.
