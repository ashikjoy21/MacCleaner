# MacCleaner UI brief

Build the SwiftUI interface for MacCleaner, a Mac app that shows how much disk space can be freed and cleans it up.
The engine is done and lives in `Sources/CleanerKit`. Your job is the app in `Sources/MacCleaner` only.

## Goal

It should look and feel like Apple made it, as if it were a panel of System Settings or a first-party utility
like Disk Utility. Someone opens it, immediately sees **"You can free up 17 GB"**, understands what each part is,
and can see technically what will be removed before clicking one button.

## Hard rules

- Only edit files under `Sources/MacCleaner/`. Do not change `Sources/CleanerKit`, `Package.swift` or tests.
  If the engine is missing something you need, say so in your final message instead of changing it.
- macOS 14+, SwiftUI only (AppKit only where SwiftUI has no equivalent). Use `@Observable`.
- System look only: system fonts and text styles, semantic colors (`.primary`, `.secondary`, `.tint`, `Color(nsColor:)`),
  SF Symbols, native controls, materials. No custom fonts, no hard-coded hex colors, no gradients or glossy custom chrome.
  Must look right in light and dark mode and with any accent color.
- Use Apple's own layouts: `NavigationSplitView`, `Table`, `Form` with `.formStyle(.grouped)`, `GroupBox`,
  `.toolbar`, sheets for confirmation. Follow the macOS Human Interface Guidelines.
- `swift build` must succeed with no errors. Run it and fix everything before finishing.
- Add accessibility labels for icons and the usage bar.

## Engine API (read `Sources/CleanerKit/Models.swift` and `CleanupEngine.swift`)

- `CleanupEngine()`: `scan() -> AsyncStream<CategoryResult>` yields each category as it finishes (the whole scan takes 30–60 s);
  `clean(_ items:, appsToQuit:, progress:) async -> CleanReport`.
- `CategoryResult`: `id, name, summary` (one plain sentence), `explanation` (technical paragraph), `symbol` (SF Symbol),
  `safety: Safety` (`.regenerates` / `.recoverable` / `.review`, with `.label`), `appToQuit: AppIdentity?`, `items`,
  `status` (`.ready`, `.needsFullDiskAccess`, `.unavailable(reason)`), `totalSize`, `isVisible` (hide categories where this is false).
- `CleanupItem`: `id, title, subtitle, paths, size, method: RemovalMethod` (`.label` is "Deleted" / "Moved to Trash" / "Runs a command"),
  `isSelectedByDefault`, `lastModified`, `displayPath`, `technicalDescription` (the exact `rm -rf …`, `mv …` or command).
- `DiskUsage.current()`: total, available, used, usedFraction. `FileSystem.format(bytes)` formats sizes.
  `FileSystem.relative(date)` gives "4 months ago".
- `AppControl.isRunning(app)`. `Permissions.openFullDiskAccessSettings()`, `Permissions.reveal(url)`.

## Screens

### Window
`NavigationSplitView`. Sidebar: an **Overview** row, then one row per visible category (SF Symbol, name,
selected size as trailing secondary text). Toolbar: a Rescan button (`arrow.clockwise`), disabled while scanning or cleaning.
Minimum window size around 900×600. Scanning starts automatically on launch.

### Overview (default selection)
- Headline: **"You can free up 17.03 GB"** in a large title style, computed from currently ticked items. Below it, in secondary text:
  "Selected from 7 categories · 108.8 GB available on Macintosh HD".
- A storage bar in the style of System Settings › General › Storage: used space, the part of it that is selected for cleanup
  (highlighted in the accent color), and free space, with a small legend underneath.
- A grouped list of categories, one row each: icon, name, the one-line summary, a safety badge (`safety.label`), size,
  and a checkbox that ticks or unticks the whole category (mixed state when partially ticked). Clicking the row opens the category.
- While scanning: a small inline `ProgressView` with "Scanning…" and categories appearing as they arrive. The headline counts up as results come in.
- Primary button at the bottom right: **Clean Up…** (`.borderedProminent`, large control size), disabled when nothing is ticked.

### Category detail
- Header: large symbol, name, total and selected size, safety badge.
- "What this is": `summary`, then `explanation` in secondary text.
- A `Table` of items: checkbox column, Name (`title` with `subtitle` underneath in secondary), Location (`displayPath`, monospaced,
  truncating in the middle), Last changed (`relative(lastModified)`), How (`method.label`), Size (right-aligned). Sortable by size and name.
  Context menu on a row: "Show in Finder" (`Permissions.reveal`) when the item has paths, "Copy Command" (`technicalDescription`).
- Under the table, a disclosure group **"What will run"** that shows the `technicalDescription` of each ticked item in a
  monospaced, selectable text block, so technical users can see exactly what happens.
- "Select All" / "Select None" buttons.
- If `appToQuit` is set and the app is running, show an inline note: "WhatsApp will be quit before cleaning."
- If status is `.needsFullDiskAccess`: instead of the table, show a centered explanation (`ContentUnavailableView` style):
  "MacCleaner needs Full Disk Access to look at WhatsApp's files", and an "Open System Settings" button that calls
  `Permissions.openFullDiskAccessSettings()`, plus a hint to relaunch afterwards.

### Confirmation sheet (after Clean Up…)
Title "Clean Up 17.03 GB?". Lists each category with ticked size and how it's removed, grouped as
"Deleted permanently (rebuilds automatically)", "Moved to Trash" and "Commands", with totals. If any app must be quit,
a warning line naming it. Buttons: Cancel (default escape) and **Clean Up** (prominent).

### Cleaning and result
While cleaning: a sheet with a determinate `ProgressView` (from `CleanProgress`) and the current item title.
When done: a result view (in the same sheet) with a large checkmark symbol, **"Freed 12.4 GB"** (`deletedBytes`),
and if `trashedBytes > 0`: "11.3 GB was moved to the Trash. Empty the Trash to free that space." with an
"Open Trash" button (opens `~/.Trash` in Finder). If there are failures, a disclosure group listing them.
A Done button closes it and rescans.

## Structure suggestion

`MacCleanerApp.swift` (scene, window size, commands), `AppModel.swift` (`@Observable @MainActor` model: results keyed by id,
`selectedItemIDs: Set<String>` initialised from `isSelectedByDefault`, computed selected bytes, scan/clean functions),
`SidebarView.swift`, `OverviewView.swift`, `StorageBar.swift`, `CategoryDetailView.swift`, `CleanSheet.swift`.
Keep views small and previewable. Use `#Preview` with sample data where useful.

When finished, reply with a short summary of the files you created and anything in the engine you'd want changed.
