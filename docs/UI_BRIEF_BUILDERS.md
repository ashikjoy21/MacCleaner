# MacCleaner UI update: built for builders

MacCleaner is now aimed at developers. The engine in `Sources/CleanerKit` has changed; update the SwiftUI app in
`Sources/MacCleaner` to match. Everything in `docs/UI_BRIEF.md` still applies (Apple look, native controls, only edit
`Sources/MacCleaner`, `swift build` must pass). This brief lists only what changes.

## Engine changes you need to use

- `CategoryResult.section: CategorySection` (`.projects`, `.developerTools`, `.aiTools`, `.otherApps`; `Comparable`, has `.title`).
- `CleanupItem.gitBranch: String?` and `CleanupItem.lastCommit: Date?` (set for project items).
- `ShellScript.make(for: items, appsToQuit: apps) -> String`: a reviewable zsh script that does exactly what Clean Up would do.
- New categories appear automatically: Simulators, Android & Gradle, Code Editors, Toolchains & Runtimes, AI Coding History.

## Changes

1. **Sections everywhere.** Group categories by `section` in the sidebar (`Section(section.title)`) and in the Overview list
   (a small section header above each group). Order sections by `CategorySection` order; within a section, largest first.
   Projects come first.

2. **Projects front and centre.** The Overview gets a "Projects" block at the top, above the other sections: the five largest
   project items as compact rows (project name, artifact folder, branch in a small capsule using `.secondary` text,
   "last commit 3 weeks ago", size, checkbox) with a "Show All Projects" button that selects the Project Build Files category.
   In the Project Build Files detail table, add **Branch** and **Last commit** columns (sortable by last commit), and keep
   Location. Stale projects are already ticked by the engine.

3. **Terminal-friendly.**
   - Toolbar button "Copy as Shell Script" (`terminal` symbol) that copies `ShellScript.make` for the current selection to the
     pasteboard, and a "Save Shell Script…" item in the File menu that saves it with `NSSavePanel` as `maccleaner-cleanup.sh`.
   - In the confirmation sheet, add a secondary "Copy Script" button on the left, next to Cancel/Clean Up.
   - In the category detail, rename the disclosure to "Commands" and show the ticked items' commands there.
   - Keyboard shortcuts: ⌘R Rescan, ⌘⇧C Copy as Shell Script, ⌘⌫ Clean Up….

4. **Overview headline** stays "You can free up X", with the secondary line changed to
   "Across N projects and M tools · X available on Macintosh HD".

5. **Tone.** Builders read the details: keep the technical `explanation` visible (not hidden behind a disclosure) and show
   item subtitles in full. Don't add marketing copy.

When done, run `swift build`, fix any errors, and reply with a short summary of what changed.
