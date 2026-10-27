# MacCleaner

See what's using your Mac's disk, down to the folder, and free it safely. Built for developers: it knows about
`node_modules`, DerivedData, simulators, Docker, Gradle, editor leftovers and local AI models, and it always shows
the exact path or command before anything is removed.

## Install

```bash
curl -fsSL https://github.com/ashikjoy21/MacCleaner/releases/latest/download/install.sh | sh
```

The script downloads the latest release, checks its SHA-256, installs **MacCleaner.app** into `/Applications`
(or `~/Applications`), links the `maccleaner` command-line tool and opens the app. Requires macOS 14 Sonoma or later,
on Apple silicon or Intel.

On first launch MacCleaner asks for **Full Disk Access** (System Settings › Privacy & Security), which it needs to
look inside other apps' data and the Trash. Scanning works without it; those categories are just skipped.

**Update:** MacCleaner checks for new versions once a day and shows an Update button (or use *MacCleaner › Check for
Updates…*). Running the install command again also updates.

**Uninstall:**

```bash
curl -fsSL https://github.com/ashikjoy21/MacCleaner/releases/latest/download/install.sh | sh -s -- --uninstall
```

## What it finds

| Section | Categories |
|---|---|
| Projects | `node_modules`, `.next`, `build`, `.dart_tool`, `target`… in your code folders, with git branch and last commit; inactive projects ticked |
| Developer Tools | Docker, simulators, Xcode, Android & Gradle, code editors (old extension versions, caches), Homebrew, Node versions, package-manager caches |
| AI Tools | Local models (Ollama, Hugging Face, LM Studio), old Codex and Claude Code transcripts |
| macOS | Downloaded Aerial wallpaper videos, the Trash |
| Files | Large old files and installers, exact duplicates, hidden tool folders (`~/.gradle`, `~/.gemini`, `~/.rustup`…) |
| Other Apps | Chrome site storage, browser caches, WhatsApp leftover media, Telegram cache |

Plus a **File Browser** to drill into any folder with sizes, Quick Look (Space) and Move to Trash.

## Safety

- Scanning only reads. Nothing is removed until you review it and confirm.
- Caches that rebuild themselves are deleted; anything personal goes to the **Trash with Put Back**.
- Personal data, active projects and anything that can't be recreated start **unticked**.
- Apps whose data is cleaned (WhatsApp, Telegram, Chrome) are quit first.
- Credentials (`~/.ssh`, `~/.aws`, `~/.kube`), installed tools and system folders are never listed.
- Any selection can be copied or saved as a **shell script** to review or run yourself.

## Command line

```bash
maccleaner                       # summary of every category
maccleaner --items               # with each item
maccleaner telegram docker       # only these categories
maccleaner --json                # for scripts and CI
maccleaner script                # print a shell script for the default selection
maccleaner clean --yes           # clean the default selection
```

## Shortcuts, Spotlight and Finder

- Shortcuts and Siri: *How much can MacCleaner free up?*, *Clean Docker with MacCleaner*.
- Finder: right-click a project folder › Services › **Clean Build Files with MacCleaner**.

## Build from source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
swift test                          # engine tests
scripts/build-app.sh --install      # build and install into /Applications
scripts/release.sh 1.2.0            # build a release into dist/
scripts/release.sh 1.2.0 --publish  # tag, push and upload to GitHub Releases
```

The engine (`Sources/CleanerKit`) is a Swift package shared by the app and the CLI.
