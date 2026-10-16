# Changelog

Versions follow the milestones in [ROADMAP.md](ROADMAP.md). The release
workflow publishes the section for a version as its release notes.

## [Unreleased]

### Added
- Slash commands: typing `/` at the start of a line or after a space opens a
  menu of blocks to make — headings, lists, quotes, code, Mermaid and math
  blocks, tables, dividers, links, images, footnotes and a table of contents.
  Typing narrows it, ↑↓ and Return choose, Escape leaves the `/` as typed, and
  one undo brings the typed command back.

## [1.0.2] - 2026-10-14

### Fixed
- The caret on an empty document is the same height as on a line of text.
  It was sized from the typing attributes, which carried no line height.

## [1.0.1] - 2026-10-13

### Fixed
- The disk image installs with Homebrew on macOS 27. The 1.0.0 image had a
  flaw that macOS 27's `hdiutil` rejects as corrupt; the app inside is
  unchanged.

## [1.0.0] - 2026-10-13

The App Sandbox, and a round of security fixes.

### Breaking
- MdEdit now runs in the App Sandbox, which keeps its data in
  `~/Library/Containers/com.mdedit.MdEdit`. Settings, custom themes, version
  history and the last session from 0.9 are not carried over. To keep your
  themes, copy them from `~/Library/Application Support/MdEdit/Themes` to
  `~/Library/Containers/com.mdedit.MdEdit/Data/Library/Application Support/MdEdit/Themes`.
- `mdedit --render` can no longer `--embed-images`: the sandboxed app cannot
  read the images.

### Security
- Release builds run in the App Sandbox. The `mdedit` command is now a small
  script, `MdEdit.app/Contents/Helpers/mdedit`, that opens the files it is
  given and passes them to the sandboxed app, so markdown from the command
  line is rendered inside the sandbox too. `mdedit file.md` opens the file in
  the app. `--embed-images` needs an unsandboxed build.
- ⌘-clicking a link no longer runs programs or scripts: apps, `.command`,
  shell scripts and other executables are shown in Finder instead. Links with
  schemes other than `http`, `https` and `mailto` ask before opening.
- KaTeX and Mermaid are checked against pinned SHA-256 hashes when bundled,
  and exported pages load them from the CDN with Subresource Integrity.
- Exported HTML drops `javascript:`, `vbscript:` and non-image `data:` URLs.
- Web images over 50 MB are not loaded; the math and diagram web view cannot
  navigate away from its page; the update checker only opens GitHub pages.

## [0.9.3] - 2026-10-12

Tab shortcuts and animations.

### Added
- ⌘1…⌘8 go to a tab by position and ⌘9 to the last (View ▸ Go to Tab);
  ⌃Tab and ⌃⇧Tab cycle tabs; File ▸ Reopen Closed Tab (⇧⌘T) brings back
  closed files.
- Tabs animate: a new tab opens out as its neighbours make room, a closed one
  folds away, reordered tabs slide into place, and switching fades the page in
  as the thumb slides. Reduce Motion turns it all off.

## [0.9.2] - 2026-10-11

Performance, from an audit of the whole app.

### Changed
- Large documents are fast to open and work in. At 4.5 MB: opening takes 1.6 s
  (over a minute before), a theme, appearance or settings change 1.6 s (42 s),
  select all 0.6 s (32 s), the first scroll to the middle 2.0 s (4.4 s), and a
  keystroke 2.0 ms (2.9 ms).
- A loaded image or rendered formula restyles only its own lines, not the whole
  document; so does resizing the window.
- Images are decoded in the background at the size the column needs and dropped
  when no open document shows them: a 12 MP photo redraws in 3.5 ms (20 ms).
- Malformed markdown no longer stalls export or Quick Look: 68 KB of unclosed
  `<!--` rendered in 17.7 s, now 9 ms; long runs of emphasis, brackets and `$`
  are linear too.
- The Files sidebar follows changes folder by folder, ignores `.git`,
  `node_modules` and build output, and waits while hidden: a checkout or an
  install no longer makes the app stutter.
- Quick Look previews the first 1 MB of a larger file, and says so.
- Crash recovery rewrites only documents changed since their last snapshot;
  focus mode redraws only the lines entering and leaving focus; export reads
  KaTeX and Mermaid once.
- Homebrew installs MdEdit as a cask: the release's app goes into /Applications,
  ready to open, with the `mdedit` command; no Xcode or build needed.

### Fixed
- Emphasis could be dropped after an earlier match in the same paragraph:
  `_a*_*a*` rendered as `<em>a*</em>*a*`.
- Photos taken sideways show upright.

## [0.9.1] - 2026-10-09

### Fixed
- Building with Xcode 26 and its Command Line Tools, as the Homebrew formula and
  GitHub's macOS 26 runners do: a macOS 27 glass API is now guarded at compile time.
  0.9.0 built only with Xcode 27, so its release was never published.

### Changed
- CI reports compiler errors and test failures as annotations, readable without
  signing in to GitHub.

## [0.9.0] - 2026-10-09

Quality, accessibility and distribution (roadmap P3).

### Added
- VoiceOver reads the editor as it is drawn: hidden markers are skipped, bullets
  and task boxes read as such, emoji shortcodes as their emoji, formulas and
  diagrams as their source, and image lines announce themselves. The tab strip
  is a tab group with the unsaved state in each tab's name and a Close action.
- Quick Look previews of markdown files in Finder.
- MdEdit registers as the default editor for markdown, with its own document icon.
- Help ▸ Welcome to MdEdit (shown on first launch) and Help ▸ Markdown Cheat Sheet,
  both opened as editable copies.
- Check for Updates… in the app menu, and an optional daily check (Settings ▸ Editor).
- Localization: every user-facing string is localizable, collected into
  `Resources/Localizable.xcstrings` by `Scripts/update-strings.sh`.
- Distribution without a paid Apple account: a Homebrew formula that builds MdEdit
  from source (so Gatekeeper never stops it), and a DMG on GitHub Releases with
  first-launch instructions, built by a tag-triggered workflow. Developer ID signing,
  notarization and an App Sandbox build (`--sandbox`, with security-scoped bookmarks
  for the session and workspace folders) are scripted for if that changes.
- CI on macOS 26: build, test, lint (`Scripts/lint.sh`, swift-format) and app assembly.
- Tests for the Format commands, undo, window flows (closing and quitting with
  unsaved tabs, tab tear-off), typing through real key events, and large files.

### Changed
- Each document keeps its own undo history; Format, table, paste and revert edits
  are undo steps of their own, named for the command.
- Typing in large documents: two whole-document walks per keystroke are gone
  (2 MB: 6.8 → 2.0 ms a keystroke), and fonts are built once instead of per line.
- Session restore follows files renamed or moved since the last run.

### Fixed
- Undo in one tab could undo an edit in another tab of the same window.
- Undoing a list continuation, auto-paired bracket, indent or fence close threw an
  exception: each was recorded twice.
- `- ` right after a list item was read as a heading underline, turning the item
  above into a heading and stopping Return from ending the list.

## [0.6.0] - 2026-10-08

Workspaces and power features (roadmap P1–P2): file tree, outline, Quick Open,
Find in Folder, multiple windows and tab tear-off; settings, themes and theme
files; export options, paginated PDF and print, Word/RTF/text, Pandoc and the
`--render` command line; statistics and word goals, folding, several carets,
table of contents and version history; math and Mermaid typeset in the editor.

## [0.5.0]

Tables and math: table editing, inline and display math, Mermaid in export.

## [0.4.0]

Rich editing: inline images, clickable tasks and links, image paste and drop,
rich-text paste, source mode, code block language picker.

## [0.3.0]

Complete syntax: reference links, footnotes, front matter, HTML blocks, bare
autolinks, highlights, sub/superscript, emoji, and the CommonMark spec suite.

## [0.2.0]

Safe: unsaved-change review on quit and close, autosave and crash recovery,
session restore, encoding and line-ending fidelity.

## [0.1.0]

The in-place WYSIWYG editor: incremental parsing, concealed markers, tabs, find
and replace, formatting commands, typewriter and focus modes, HTML and PDF export.
