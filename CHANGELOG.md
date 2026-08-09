# Changelog

All notable changes to this project will be documented in this file.

The project uses semantic versioning once a public release is created.

## 0.7.1 - 2026-08-09

- Suppress Plasma's generic metadata tooltip so the compact status tooltip is
  the only popup shown when hovering the panel icon.
- Give short screens a taller, safely capped popup and keep the New chat risk
  warning and launch button visible while its options scroll independently.
- Use the packaged Codex Blossom in Plasma's widget explorer and edit mode.

## 0.7.0 - 2026-08-08

- Detect supported terminal emulators and add an optional persistent selector
  with automatic fallback when Konsole is unavailable.
- Use the selected terminal for both fresh chats and resumed history entries.
- Keep terminal commands behind a closed adapter allowlist and pass Codex
  arguments without a shell.
- Add initial public-release documentation, a synthetic English screenshot,
  and basic GitHub Actions tests.

## 0.6.0 - Local development build

- Add an optional native folder picker for choosing the working directory of a
  fresh Codex CLI session.
- Preserve the existing home-folder default when no directory is selected.
- Validate the selected directory before passing it separately to Konsole and
  Codex, including paths with spaces.

## 0.5.5 - Local development build

- Align New chat content to the top and place flexible space below it, matching
  the Status tab layout.
- Set the representation's implicit height as well as its layout hints.
- Rename the Chats tab to History to distinguish it from New chat.

## 0.5.4 - Local development build

- Keep one stable popup height across Status, New chat, and Chats.
- Remove the redundant separator and double spacing above the New chat
  controls.

## 0.5.3 - Local development build

- Move the complete CLI launcher into a dedicated New chat tab so the Status
  view and footer fit without vertical scrolling.

## 0.5.2 - Local development build

- Increase the popup's preferred width and height so the complete launcher and
  footer remain visible, while respecting the screen's available area.

## 0.5.1 - Local development build

- Keep the fresh CLI launcher independent of shell configuration by offering
  model, reasoning, official sandbox mode, and approval policy only.
- Default every launch selector to the existing Codex configuration.
- Offer the official approval-and-sandbox bypass only after two explicit
  button confirmations.

## 0.5.0 - Local development build

- Replace typed bulk-delete confirmation with two consecutive button dialogs.
- Add twice-confirmed use of an available limit reset through app-server with
  an idempotency key.
- Add a fresh CLI launcher with dynamic picker-visible models and reasoning
  efforts.
- Avoid shell aliases and automatic prompts.

## 0.4.1 - Local development build

- Fix a runtime-only QML error caused by assigning the read-only
  `implicitWidth` property on dialog content items.

## 0.4.0 - Local development build

- Offer confirmed permanent deletion for active chats as well as archived
  chats.
- Add typed-confirmation bulk deletion for all archived chats.
- Collect and validate every archived UUID before bulk deletion starts, with
  repeated-cursor detection and a 1,000-thread safety limit.
- Report possible partial completion if Codex fails during sequential bulk
  deletion.

## 0.3.0 - Local development build

- Group active and archived chats into separate visual sections.
- Add a confirmed permanent-delete action for archived chats through
  `thread/delete`.

## 0.2.3 - Local development build

- Fix thread helper arguments being replaced by JavaScript's implicit
  `arguments` object in QML.

## 0.2.2 - Local development build

- Load the chat model when the widget starts instead of relying on tab events.
- Render the dynamic chat model in a dedicated list view.
- Track the single pending helper operation independently of its command text.

## 0.2.1 - Local development build

- Include active and archived chats in the default Chats view.
- Restore an archived chat only when the user explicitly opens it.
- Show the addon version in the popup so the loaded build is unambiguous.

## 0.2.0 - Local development build

- List and search saved interactive chats through documented app-server APIs.
- Rename saved chats through `thread/name/set`.
- Resume a validated thread UUID in a separate Konsole process.
- Keep chat titles, UUIDs, timestamps, and status in memory only.
- Add fictional normalization and command-safety tests for thread operations.
- Add Status and Chats views in English and Spanish.
- Keep the compact Codex icon and percentage visible while data refreshes.

## 0.1.0 - Local prototype

- Add a read-only Codex app-server adapter with a strict output allowlist.
- Show authentication state and plan without exposing account identity.
- Show available usage windows, remaining percentages, and reset times.
- Show optional aggregate token activity and available limit-reset count.
- Add manual and periodic refresh plus a configurable compact panel indicator.
- Add the official Codex service icon for light and dark Plasma themes.
- Add English source strings and a Spanish translation.
- Document the public project's privacy and security boundaries.
