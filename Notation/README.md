# Notation

A capture-and-retrieve plain-text notebook for iPhone and iPad, modeled on the interaction of
[Notational Velocity](https://notational.net/): one field finds a note or creates it. Clean-room Swift/SwiftUI
implementation (iOS 17+); no code from the GPL Objective-C original.

> **Status: written without a compiler.** This was authored in a Linux container with no Xcode, so it has never
> been built or run. Expect to fix a few compile errors on first build (most likely around the SwiftyDropbox
> calls in `Sync/SwiftyDropboxAPI.swift`). The logic is covered by unit tests in `NotationTests/` that have also
> not been run yet.

## Build

1. Xcode 16 or later. Open `Notation/Notation.xcodeproj` (it uses folder-synced groups, so new Swift files
   are picked up automatically). If it ever misbehaves, `xcodegen generate` rebuilds it from `project.yml`.
2. Xcode resolves the SwiftyDropbox package on first open.
3. Set your Team and a unique bundle identifier (`com.example.Notation` is a placeholder) under Signing.
4. Run on an iPhone or iPad simulator. **Notes work immediately with no Dropbox setup**; they are stored on
   the device. Sync is added by the steps below.

## Dropbox setup

1. Create an app at <https://www.dropbox.com/developers/apps>: **Scoped access**, then **App folder**
   (recommended: the app only sees `Dropbox/Apps/<your app name>`). Full Dropbox also works.
2. **Permissions** tab: enable `files.metadata.read`, `files.content.read`, `files.content.write`. Submit.
3. **Settings** tab, *OAuth 2 → Redirect URIs*: add
   `db-<YOUR_APP_KEY>://1/connect` (the app key is on the same page). Leave *Allow public clients (Implicit Grant & PKCE)* enabled.
4. Copy `Config.example.plist` to `Config.plist` (same folder; it is gitignored) and fill in:
   - `DropboxAppKey`: your app key
   - `DropboxAccessType`: `appFolder` or `fullDropbox`
   - `DropboxFolderPath`: optional override of the default folder
5. Build and run, tap the gear, **Connect Dropbox**. Sign-in uses `ASWebAuthenticationSession` (OAuth 2 code
   flow with PKCE). Access and refresh tokens are stored in the Keychain.

Without `Config.plist`, a build warning says so and the app runs local-only.

### Which folder

- App-folder apps: the app folder itself (shown by Dropbox as `/Apps/<name>`) is the default.
- Full-Dropbox apps: default `/Apps/Notation`.
- Either way, gear → **Change folder** browses your Dropbox folders and lets you pick another one. Notes already
  on this device are reconciled with that folder by file name. Dropbox's own Chooser SDK is deprecated and has no
  Swift API, so the picker is built in.
- Any other editor or app can open the same `.txt` files in that folder.

## How it behaves

**One field.** The placeholder is “Search or Create”. Every keystroke filters the list against titles and bodies:
a note matches when every whitespace-separated word appears in its title or body, case-insensitively. Ranking is
title-prefix, then title-contains, then body-only, then most recently modified. An empty field shows every note.

**Selection.** If the text is exactly a title, or a prefix of exactly one title, that note opens in the editor
but your typing is left alone. Up/Down (hardware keyboard) or a tap highlights a row; Return or a tap confirms it,
putting its title in the field. Clearing the field after that restores your previous query and list.

**Return.** On a highlighted note: focus its body. Otherwise, if the text isn't an existing title, it creates
`Title.txt`, selects it, and focuses the body. (Typing `Foo` when `Foobar` exists therefore creates `Foo`; the
auto-highlighted `Foobar` is only opened if you press Down or tap it.)

**Files.** One note, one UTF-8 `.txt` file; the filename is the title. Edits are written 300 ms after you stop typing;
there is no Save button. Titles lose path separators and characters Dropbox rejects (`/ \ : < > " | ? *`),
leading dots, and extra whitespace, and are capped at 120 characters.

**Rename, delete.** Long-press a row → Rename (or ⌘R) edits the title in place and renames the file; if the name is
taken it is refused and the old name stays. Swipe a row (or ⌘⇧⌫) to delete: the file moves to `Notes/.Trash`
inside the local notes folder, with Undo for 5 seconds. Deletes and renames reach Dropbox at the next sync, at least 10 seconds later.

**Hardware keyboard.** ⌘L / ⌘F focus the field, ⌘N clears it and the selection, Esc returns to the field and clears
the selection, ↑/↓ move the highlight.

**Sync.** On launch, on returning to the foreground, a few seconds after edits, and via **Sync now** in Settings:

- Newer on Dropbox (by revision) and no local edits → download.
- Local edits and Dropbox unchanged → upload.
- Both changed → your edit stays as `Title.txt`; the Dropbox version is saved as
  `Title (Dropbox conflict YYYY-MM-DD).txt` and both are uploaded. A one-line notice appears under the field.
- Removed on Dropbox with no local edits → removed locally (moved to `.Trash`).
- Search never touches the network; it scans an in-memory index built from the local files.
- Offline: editing continues, uploads wait, and a small “offline” caption appears next to the field.
- Ignored: hidden files, non-`.txt` files, and Dropbox's own `(conflicted copy)` files.

**Local storage.** `Application Support/Notes/` mirrors the Dropbox folder. `Application Support/notes-index.json`
holds path, title, mtime, rev, sync flags, and a body snippet. It is only a cache; if it is missing the index is
rebuilt from the files.

## Settings (gear)

Connect / disconnect / change folder, last sync time and **Sync now**, sort (Modified or Title), font size stepper.
The divider between the list and the editor can be dragged.

## Layout

```
Notation/
  NotationApp.swift        entry point; wires store, model, sync
  Model/                   Note + filename rules, SearchEngine, NoteStore, NotebookModel
  Sync/                    DropboxConfig, DropboxAuth (PKCE), SyncEngine, SwiftyDropboxAPI, DropboxSync
  Views/                   NotebookView, SearchField, NoteList, NoteEditor, SettingsView
  Support/                 Theme, AppSettings
NotationTests/             search, filename rules, store, sync engine (fake Dropbox)
```

## Decisions worth knowing

- **No sign-in gate.** The app opens straight to the notebook and is fully usable offline/local-only; Dropbox is
  connected from Settings.
- **Own OAuth, SDK for the API.** SwiftyDropbox's built-in sign-in uses `SFSafariViewController`; the brief asked
  for `ASWebAuthenticationSession`, so `DropboxAuth` runs the PKCE flow and hands short-lived access tokens to the SDK.
- **Rename.** Notational Velocity renames from the list row, so that is what is done here; the field stays a search field.
- **Out of scope in v1:** folders, tags, markdown preview, rich text, widgets, encryption, Simplenote.
