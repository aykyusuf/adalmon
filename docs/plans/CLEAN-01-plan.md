# CLEAN-02 plan: built-in disk cleaner ("Temizlik") for Adalmon

## Goal and constraints
Build a small cleaner that is our own code. The flow is:
1. The user starts a scan by hand.
2. A preview shows each item's path, size and category.
3. The user confirms.
4. The items move to the Trash with `FileManager.trashItem`. Nothing is ever deleted permanently.
5. Each move is written to a log.

Only allowlisted user folders are in scope. Symlinks are skipped. System paths and TCC-protected paths are never touched unless the user starts that scan explicitly. Permission errors are handled quietly. Caches of running apps are skipped.

Battery limits from STATUS ("pil yemesin"):
- Scans run only on demand, off the main thread, and can be cancelled.
- There are no timers and no background scans.
- Cleaner roots are never added to the hourly `ResourceService` loop.

Other constraints:
- Do not break the existing layout.
- No reboot.
- Mole (GPL-3.0) is a reference only, for which folders are safe. No Mole code is copied.
- Keep it lean.

## Verified facts this plan relies on (seen in code)
- `Sources/App/Process/FolderScanner.swift` already provides `FolderScanner.scan(root:minRecordedBytes:isCancelled:)`. It uses `getattrlistbulk` with allocated sizes, counts hard links once, opens with `O_NOFOLLOW`, takes an `isCancelled` closure, and records child directories up to `maxDepth`. Reuse it; do not write a new walker. The tests are in `Tests/FolderScannerTests.swift` and use temp-dir fixtures with a non-sparse `write` helper.
- `scan` returns nil only when `lstat` fails or the root is not a directory. When the root exists but `open()` fails, it counts the root as unreadable and returns a 0-byte Result (`size(of:)`).
- The Result always appends a depth-0 entry for the root itself.
- Whether `skipChildNames` applies only to the root's direct children is an ASSUMPTION, because the tool output was truncated. `validate` re-checks names anyway.
- `FolderWatchList.cachesSkipNames` (Safari, Mail, Maps, Photos, Messages, CloudKit, and others) and `FolderWatchList.displayPath(_:home:)` (shows `~`) are in the same file. `MobileSync` is deliberately skipped in `appSupportSkipNames`.
- `Sources/App/Process/ResourceService.swift:42-94` runs the hourly `FolderWatchList` scan. Do not touch it.
- `trashItem` appears nowhere in `Sources/` today (grep checked). The new code will be the only call site.
- `AppEnvironment.supportDirectory` (`Sources/App/App/AppEnvironment.swift:12`) points to `~/Library/Application Support/Adalmon`. Under XCTest it points to a per-process temp dir.
- The Processes page has tabs (`ProcessesTab.swift`: processes, performance, browsers, history, startup, disk), dispatched in `ProcessesPage.swift:27-35`. `CapsuleTabBar` (`ViewThatFits`) falls back to icons only when space is narrow, so a 7th tab does not overflow.
- Sidebar pages are in `MainSection.pages` (9 pages, shortcuts ⌘1 to ⌘9). `shortcutKey` would return "10" for a 10th page. `Tests/MainWindowPagesTests.swift:9-10` asserts the exact list and shortcut keys.
- `Tests/ProcessesTabTests.swift:10` asserts `ProcessesTab.disk.neighbor(1) == .disk` (disk is the last tab). Line 14 asserts that the `systemImage` values are unique.
- These pieces can be reused:
  - `ResourceCard(title:systemImage:)` in `ResourceRankRow.swift:43`
  - `Format.bytes(UInt64)` in `Sources/App/UI/Components/Format.swift:8`
  - the Finder-reveal pattern at `ProcessDiskView.swift:149-156`
  - the System Settings deep-link pattern at `BrowserTabsView.swift:150`
- `project.yml` facts:
  - Not sandboxed (no `app-sandbox` key); hardened runtime is on.
  - `SWIFT_STRICT_CONCURRENCY: complete`.
  - The test target is `AdalmonTests` (sources: `Tests`).
  - New files under `Sources/App` are picked up by `xcodegen generate`.

## Placement (needs user decision, see Questions)
- **A (recommended): a new "Temizlik" tab after "Disk" on the Süreçler page.**
  - Changes: a `ProcessesTab` case plus one switch line.
  - Sidebar and ⌘1 to ⌘9 stay as they are.
  - One test changes: `ProcessesTabTests` line 10.
  - Cost: the feature is one level deeper in the UI.
- **B: a new sidebar page.**
  - Changes: a `MainSection.cleanup` case, `MainWindowDetail` switch, title, symbol and tint.
  - `shortcutKey` must return nil for index ≥ 9.
  - Update `MainWindowPagesTests` lines 9-10.
  - Cost: the sidebar layout changes, and the 10th page has no shortcut.

The rest of the plan assumes A. For B, swap the two placement files.

## Categories (exact paths; H = home, injectable)
Each category has one or more roots. **An item is always a direct child of a root (depth 1).** A root itself is never an item.

| id | Turkish label | root(s) | items | default selected |
|---|---|---|---|---|
| appCaches | Uygulama önbellekleri | `H/Library/Caches` | each child directory, except: `FolderWatchList.cachesSkipNames`, any name with the `com.apple.` prefix, Adalmon's own bundle id, and the names owned by pkgCaches (`Homebrew`, `pip`, `Yarn`, `pnpm`) | yes, unless the app is running |
| derivedData | Xcode DerivedData | `H/Library/Developer/Xcode/DerivedData` | each child | yes, unless Xcode is running |
| archives | Xcode arşivleri | `H/Library/Developer/Xcode/Archives` | each child (date folders) | **no** (they hold dSYMs) |
| deviceSupport | Cihaz destek dosyaları | `H/Library/Developer/Xcode/{iOS,watchOS,tvOS,visionOS,macOS} DeviceSupport` | each child | **no** |
| simCaches | Simülatör önbellekleri | `H/Library/Developer/CoreSimulator/Caches` | each child. `CoreSimulator/Devices` is never a root | yes, unless Simulator is running |
| pkgCaches | Paket yöneticisi önbellekleri | `H/.npm` (only the child `_cacache`), `H/Library/Caches/Homebrew`, `H/Library/Caches/pip`, `H/Library/Caches/Yarn`, `H/Library/pnpm/store` | each child (for npm, only `_cacache`) | yes |
| iosBackups | iOS yedekleri | `H/Library/Application Support/MobileSync/Backup` | each child (one per device backup) | **no**. Listed only; the user may tick an item by hand |
| downloads | İndirilenler | `H/Downloads` | top-level entries (files or folders) with size ≥ 100 MB **or** last modified more than 90 days ago (and size ≥ 1 MB) | **no**. Listed only |
| trash | Çöp Sepeti | `H/.Trash` | none. Shows the total size only; it has no actions | n/a |

Rules:
- `~/Library/Logs` is deliberately left out. The research doc mentions it, but the user's list does not include it.
- Dedupe: a folder belongs to exactly one category. appCaches excludes the pkgCaches names.
- The minimum size to list a row is 1 MB. Smaller items are not shown, not counted and never trashed.
- Running apps: get the bundle IDs from `NSWorkspace.shared.runningApplications` (an injectable `Set<String>`). A cache child whose name matches a running bundle ID gets the badge "Açık", its checkbox is disabled, and it is skipped again at trash time. DerivedData and simCaches behave the same way when `com.apple.dt.Xcode` or `com.apple.iphonesimulator` is running.

## Scanning strategy
- **The default "Tara" button scans only the non-TCC roots:** appCaches, derivedData, archives, deviceSupport, simCaches and pkgCaches. Downloads, iOS backups and Trash each have their own button on their card ("İndirilenleri tara", "Yedekleri tara", "Hesapla"), so the user decides when a permission prompt may appear. Never touch these three in the default scan.
- **Probe each root first** with `open(path, O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)` and branch on the result:
  - errno ENOENT or ENOTDIR: the category is hidden.
  - errno EPERM or EACCES: state `.noAccess`, which shows "Erişim yok. Tam Disk Erişimi gerekebilir" and a button "Ayarları aç". The button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
  - success: `close` the descriptor, then scan.

  This probe is needed because `FolderScanner.scan` returns a 0-byte Result for a TCC-denied root, not nil.
- Size per root:
  - Call `FolderScanner.scan(root: FolderScanRoot(path: root, maxDepth: 1, skipChildNames: skips), minRecordedBytes: 1 << 20, isCancelled: { Task.isCancelled })`.
  - Only the `depth == 1` entries become rows; ignore the depth-0 root entry. This is one traversal per root.
  - `FolderSnapshotEntry` has only path, depth and bytes. The scanner therefore `lstat`s each depth-1 row once to record `st_dev` and `st_ino`, and drops it if it is a symlink.
  - Children that are plain files (Downloads, and stray files in caches) are measured with one `lstat` and `st_blocks * 512`. Symlinks (`S_IFLNK`) are always skipped.
  - Downloads needs file rows, so list it with `FileManager.contentsOfDirectory(at:includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .totalFileAllocatedSizeKey], options: [.skipsHiddenFiles])` and size subfolders with `FolderScanner`. If this throws EPERM, the state is `.noAccess` as above.
- Unreadable subfolders are counted quietly, with no alert.
- Threading:
  - `Task.detached(priority: .utility)`; the results are published back on `@MainActor`.
  - Roots are scanned one after another, not in parallel.
  - "Durdur" cancels the task. Leaving the tab (`onDisappear`) also cancels it.
  - Results stay in memory only. Nothing is persisted. Nothing is re-scanned automatically.
- Cost: a cache scan reads metadata only (`getattrlistbulk`). A large DerivedData can take a few seconds. Show "Taranıyor: <kategori>…". This is an assumption, not measured; time one real scan once, by hand, after the tests pass.
- Downloads triggers the one-time macOS Downloads-folder consent prompt.
  - Add `NSDownloadsFolderUsageDescription: "Adalmon, İndirilenler'deki büyük ve eski dosyaları yalnızca siz 'İndirilenleri tara' dediğinizde listelemek için erişir."` to `project.yml` info properties. It is optional for a non-sandboxed app; this is an assumption.
  - Never probe Downloads, MobileSync or `.Trash` from a shell, test or agent, because that can open a TCC window.

## Data model (Sources/App/Cleanup/CleanupModel.swift)
```swift
enum CleanupCategory: String, CaseIterable, Identifiable, Sendable { case appCaches, derivedData, archives, deviceSupport, simCaches, pkgCaches, iosBackups, downloads, trash
  var title: String; var systemImage: String; var defaultSelected: Bool; var needsExplicitScan: Bool /* downloads, iosBackups, trash */ }
struct CleanupRoot: Sendable, Equatable { let category: CleanupCategory; let path: String; var onlyNames: Set<String>? = nil; var skipNames: Set<String> = []; var skipPrefixes: [String] = [] }
struct CleanupItem: Identifiable, Sendable, Equatable { let id: String /* path */; let path: String; let rootPath: String; let category: CleanupCategory
  let bytes: UInt64; let isDirectory: Bool; let modified: Date?; let dev: Int32; let ino: UInt64; var blockedReason: String? /* "Açık" */ }
enum CleanupRootState: Sendable, Equatable { case missing, noAccess, scanned }
enum CleanupCatalog { static func roots(home: String) -> [CleanupRoot] /* the table above */ }
```

## Single trash function and its guards (Sources/App/Cleanup/CleanupTrasher.swift)
```swift
struct CleanupTrasher: Sendable {
  var roots: [CleanupRoot]; var home: String; var runningBundleIDs: Set<String>
  var logURL: URL                                   // default AppEnvironment.supportDirectory/Cleanup-log.jsonl
  var trash: @Sendable (URL) throws -> URL?         // default: FileManager.default.trashItem(at:resultingItemURL:); runs inside a detached .utility task
  enum Refusal: Error, Equatable { case notAbsolute, symlink, missing, changed, notUnderAllowedRoot, isRoot, notDirectChild, nameNotAllowed, protectedPath, appRunning }
  func validate(_ item: CleanupItem) -> Refusal?    // pure; tests call it directly
  func trash(_ items: [CleanupItem]) -> [CleanupResult]   // validate each item, then trash, then append a log line; never throws, collects failures
}
```
`validate` re-checks everything at trash time, because a gap of minutes can separate the preview from the confirm. It refuses, in this order:
1. The path is not absolute, is empty, or contains `.` or `..` components.
2. `lstat` fails. The result is `missing`; a disappeared item counts as a quiet skip.
3. The item is a symlink (`S_IFLNK`).
4. `(st_dev, st_ino)` differs from the scan. The result is `changed`.
5. Canonicalize as `realpath(parent) + "/" + lastComponent`, and canonicalize each root with `realpath(root)`. Use the same function for both, because fixtures live under `/var` → `/private/var`.
6. The canonical parent must **equal** the canonical path of one allowlisted root of the item's category, compared as path components (`URL.pathComponents` arrays, not `hasPrefix`). Otherwise the result is `notUnderAllowedRoot`. The item being the root itself gives `isRoot`; anything deeper than depth 1 gives `notDirectChild`.
7. The root's `onlyNames`, `skipNames` and `skipPrefixes` (`com.apple.`, `cachesSkipNames`, the pkg names inside Caches) apply again. Otherwise `nameNotAllowed`.
8. Hard denylist, as defense in depth. A canonical path that equals, or is an ancestor of, any of these is refused (`protectedPath`):
   - `/`, `/System`, `/Library`, `/Applications`, `/usr`, `/bin`, `/sbin`, `/private`, `/Volumes`
   - `home`, `home/Library`, `home/Library/Caches`, `home/Library/Application Support`, `home/Library/Developer`
   - `home/Documents`, `home/Desktop`, `home/Downloads`, `home/Pictures`, `home/Movies`, `home/Music`
   - `home/Library/Mobile Documents`, `home/Library/Containers`, `home/Library/Group Containers`, `home/.Trash`

   Also, every allowlisted root must itself be inside `realpath(home)`.
9. A running app: the category is appCaches and the item name is in `runningBundleIDs`, or the category is derivedData/simCaches and Xcode or Simulator is running. Result: `appRunning`.

Log: one JSON line per item, appended to `logURL`:
```
{"date","category","path","bytes","trashedTo"|null,"result":"moved"|"skipped","reason"?}
```
- Write failures are ignored; the move has already happened.
- Keep only the last 500 lines.
- Rule from a past failure (STATUS Failed attempts (a)): tests once overwrote the user's real `config.json`. So every test injects `logURL`, `home` and the `trash` closure, and no test uses the real defaults.

There is **no** `removeItem`, `unlink` or `rmdir` in `Sources/App/Cleanup/` and none in the cleanup UI files. Emptying the Trash is out of scope.

## UI (Turkish labels). Files: `Sources/App/UI/MainWindow/Processes/CleanupView.swift` + `CleanupCategoryCard.swift`
Match the layout of `ProcessDiskView`: a `ScrollView` and a `VStack(spacing: 14)` of `ResourceCard`s, with `.padding(.horizontal, 24)` applied in `ProcessesPage`.
- Top row:
  - Button "Tara" (`borderedProminent`). While scanning it shows `ProgressView` + "Taranıyor: <kategori>…" and a "Durdur" button.
  - On the right: "Çöp Sepeti: <boyut>", or a small button "Çöp Sepeti: Hesapla", plus "Çöpü Finder'da aç".
- Info line, in secondary text: "Seçilenler Çöp Sepeti'ne taşınır, kalıcı silinmez. Yer, Çöp Sepeti boşaltılınca açılır."
- Empty state: "Önbellekleri ve geliştirici artıklarını görmek için Tara'ya basın. Tarama yalnızca siz isteyince yapılır."
- One `ResourceCard` per category, showing:
  - a tri-state checkbox for the whole category, the title, the total size and the count, and a disclosure for the rows. Rows are collapsed by default and capped at 200, with "+N daha".
  - On each row: a checkbox, `displayPath`, the size (`Format.bytes`), a modified date (Downloads only), a badge ("Açık" / "Erişim yok"), and a Finder-reveal button with `.help("Finder'da göster")`.
- Cards "İndirilenler" and "iOS yedekleri":
  - an explicit scan button and the note "Yalnızca listelenir, otomatik seçilmez."
  - for backups, the warning "Yedeği silmek o cihazın geri yükleme noktasını kaldırır."
  - in the `.noAccess` state: "Erişim yok. Tam Disk Erişimi gerekebilir" + "Ayarları aç".
- Bottom bar: "Seçili: N öğe · X" + "Çöp Sepeti'ne taşı…". It is disabled when nothing is selected or a scan is running.
- Confirmation dialog:
  - Title: "N öğe (X) Çöp Sepeti'ne taşınsın mı?"
  - Message: the first 5 paths + "…ve N daha", then "Kalıcı silinmez; Çöp Sepeti'nden geri alabilirsiniz."
  - Buttons: "Taşı" (`.destructive`) and "Vazgeç".
- After the move:
  - Banner: "N öğe taşındı (X). M atlandı." + "Ayrıntılar", which shows the skipped items with a Turkish reason.
  - The moved rows disappear from the list. There is no automatic re-scan.
- Card "Son işlemler" (collapsed): the last 20 log lines, each with "Çöp Sepeti'nde göster".
- The view model is `@MainActor @Observable final class CleanupViewModel` (in CleanupView.swift). It holds `items`, `rootStates`, `selection: Set<String>`, `scanTask`, `phase` and `lastResult`. The selection starts as `defaultSelected && blockedReason == nil`.

## Files to touch and order
Piece 1 (core, no UI). Can go to its own agent.
1. `Sources/App/Cleanup/CleanupModel.swift` (new): category, root, item, root state, catalog.
2. `Sources/App/Cleanup/CleanupScanner.swift` (new): `static func scan(categories:home:runningBundleIDs:isCancelled:progress:) -> (items: [CleanupItem], states: [String: CleanupRootState])`, the root probe, and `trashSize(home:) -> UInt64?`. It reuses `FolderScanner`.
3. `Sources/App/Cleanup/CleanupTrasher.swift` (new): `validate`, `trash`, the log.
4. `Tests/CleanupTests.swift` (new).

Piece 2 (UI; starts after Piece 1's types compile; disjoint files).

5. `Sources/App/UI/MainWindow/Processes/CleanupView.swift` (new) and `CleanupCategoryCard.swift` (new).
6. `Sources/App/UI/MainWindow/Processes/ProcessesTab.swift`: add `case cleanup` after `disk`, with title "Temizlik" and image "sparkles" (unique). `needsLiveSampling` stays false.
7. `Sources/App/UI/MainWindow/Processes/ProcessesPage.swift`: add `case .cleanup: CleanupView().padding(.horizontal, 24)` and update the doc comment.
8. `Tests/ProcessesTabTests.swift:10`: `.disk.neighbor(1)` becomes `.cleanup`, and add `.cleanup.neighbor(1) == .cleanup`.
9. `project.yml`: add `NSDownloadsFolderUsageDescription`. Then run `xcodegen generate`.

Run xcodegen and xcodebuild once, after both pieces. Never run two `xcodebuild`s at once (STATUS (f)).

## Test list (Tests/CleanupTests.swift)
- Every test uses a fresh fixture: `FileManager.default.temporaryDirectory/cleanup-<UUID>` as the fake `home`, removed in `tearDown`.
- Reuse the non-sparse `write(_:bytes:)` helper pattern from `FolderScannerTests`.
- `trash` is a fake `@Sendable` closure that moves into `<fixture>/FakeTrash/` with `moveItem` and records the URL. It never calls the real `trashItem`.
- `logURL` is `<fixture>/log.jsonl`.
- No test reads a real home path, Downloads, `.Trash` or MobileSync.

1. `testCatalogRootsAreUnderHomeAndDeduped`: every root starts with the fixture home. No path is a root of two categories. appCaches skips `Homebrew`, `pip`, `Yarn`, `pnpm` and `com.apple.*`.
2. `testScanListsDirectChildrenWithSizes`: `Library/Caches/com.foo/a.bin` (3 MB) and `Library/Developer/Xcode/DerivedData/Proj-abc` (2 MB) are found with the right category and size ≥ the bytes written. A child under 1 MB is not listed. No row equals a root.
3. `testScanSkipsSymlinkChildren`: a symlink in Caches that points to a big folder outside produces no item and no size.
4. `testScanSkipsAppleAndProtectedCacheNames`: `com.apple.Safari` and `CloudKit` under Caches are not listed.
5. `testDefaultScanDoesNotIncludeExplicitCategories`: with Downloads and MobileSync fixtures present, the default scan returns no items in those categories.
6. `testDefaultSelection`: archives, deviceSupport, iosBackups and downloads are not selected by default. Running-app caches get `blockedReason` and are not selected.
7. `testScanCancellation`: `isCancelled` returns true after the first call. The scan returns quickly with partial or empty results, and does not crash.
8. `testRootStates`: a root with `chmod 000` gives `.noAccess` (not an empty category, no throw). A missing root gives `.missing`. Restore the permissions in `tearDown`.
9. `testValidateRefusesRootItself`: `isRoot`.
10. `testValidateRefusesDeeperThanDirectChild`: `notDirectChild`.
11. `testValidateRefusesSiblingPrefix`: `Library/Caches2/x` gives `notUnderAllowedRoot`.
12. `testValidateRefusesDotDot`: `Library/Caches/../Preferences/x` gives `notAbsolute` or `notUnderAllowedRoot`.
13. `testValidateRefusesSymlinkSwappedAfterScan`: scan, replace the item with a symlink to `<fixture>/Documents/secret`, then trash. The result is refused, the fake trash got nothing, and the target is intact.
14. `testValidateRefusesReplacedItem`: recreate the folder with the same name; the inode differs, so the result is `changed`.
15. `testValidateRefusesProtectedPaths`: crafted items for `home`, `home/Library`, `home/Documents` are refused.
16. `testValidateRefusesRunningApp`: `runningBundleIDs = ["com.foo"]`, so `Caches/com.foo` gives `appRunning`.
17. `testTrashMovesOnlyValidItemsAndLogs`: a mixed batch. Only valid items reach the fake trash. The log has one line per item, with `moved`/`skipped` and the reason. Missing items are skipped quietly.
18. `testTrashPathCanonicalizationUnderPrivateVar`: a fixture under `/var/folders` validates OK.
19. `testLogIsCappedAt500Lines`.
20. `ProcessesTabTests` is updated, as listed above.

No new snapshot or preview test unless it is opt-in through `TEST_RUNNER_ADALMON_PREVIEW_DIR`.

## Risks and assumptions
- Assumption: reading `~/.Trash` and `MobileSync/Backup` needs Full Disk Access on macOS 26. The probe handles EPERM either way.
- Assumption: Finder's "Geri Koy" (Put Back) works for items moved by `trashItem`. The log keeps `trashedTo`. No in-app "Geri al" in v1.
- Assumption: the Homebrew, pip, Yarn, pnpm and npm caches are at their default locations (env overrides exist). Custom locations are simply not found, which is safe.
- Risk: matching a cache folder name to a running bundle ID misses caches named differently. This is accepted, because apps recreate caches.
- Risk: no space is freed until the Trash is emptied. The UI says so.
- Risk: the real scan time on a full disk is unmeasured. The scan is cancellable and runs at `.utility` priority.
- Disk is ~96% full: delete `/private/tmp/claude-501/adalmon-dd-*` (except `adalmon-dd-main`) after the build.

## Done when
All of the following hold:
1. `xcodegen generate && xcodebuild test -project Adalmon.xcodeproj -scheme Adalmon -derivedDataPath /private/tmp/claude-501/adalmon-dd-clean -only-testing:AdalmonTests/CleanupTests -only-testing:AdalmonTests/ProcessesTabTests -only-testing:AdalmonTests/FolderScannerTests` exits 0.
2. The full suite (`xcodebuild test`, same derivedDataPath) exits 0. Known exception: the 7 `BatteryLiquidGlyphTests` fail on battery in Low Power Mode (STATUS (e)).
3. `grep -rnE "removeItem|unlink\(|rmdir\(|emptyTrash" Sources/App/Cleanup Sources/App/UI/MainWindow/Processes/Cleanup*.swift` prints nothing.
4. `grep -rn "trashItem" Sources | wc -l` prints 1, and that line is in `Sources/App/Cleanup/CleanupTrasher.swift`.
5. `grep -rn "Cleanup" Sources/App/Process/ResourceService.swift` prints nothing.
6. `git status --porcelain` lists only the files above (plus the regenerated xcodeproj, and the STATUS/tasks/PROGRESS session-end files).
7. Afterwards: `rm -rf /private/tmp/claude-501/adalmon-dd-clean`.
8. User sign-off in the real app, which is manual and is needed for "done".

## Questions for the user (main session asks)
1. Placement: (A, recommended) a "Temizlik" tab under Süreçler next to "Disk", with no sidebar or shortcut change; or (B) a new 10th sidebar page with no ⌘ shortcut.
2. Running app's cache: (recommended) shown but disabled ("Açık") and skipped at trash time; or tickable after a warning.
3. Downloads thresholds: is "≥ 100 MB or not modified in 90 days" OK?
