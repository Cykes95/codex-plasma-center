# Privacy

Codex Plasma Center is designed to keep its data surface small.

## Data read by the current version

The helper asks the locally installed Codex app-server for:

- authentication type and plan;
- usage-window percentages and reset timestamps;
- optional aggregate token-activity metrics;
- the installed Codex CLI version;
- picker-visible model names and supported reasoning efforts;
- saved interactive thread UUIDs, user-facing names or title previews, update
  timestamps, and runtime statuses.

Codex may return additional fields in its protocol responses. The helper uses
an allowlist and discards everything that the widget does not need, including
email addresses, account identifiers, reset-credit identifiers, daily usage
buckets, working directories, turns, transcripts, model details, source
metadata, model descriptions, and server error details.

When the user chooses **Open in terminal**, the helper asks `thread/read` for a
summary without turns and uses a valid existing absolute working directory only
to start that local terminal in the saved location. The path is not returned to
QML, logged, cached, or stored by the addon.

When starting a new chat, a working folder chosen in the native picker exists
only in the running QML process and the launcher helper. It is validated and
used to start the selected terminal and Codex, but is not stored in the widget
configuration or returned in helper output. Leaving the picker unchanged uses
the user's home folder, as earlier versions did.

## Storage

The addon does not create an account history, cache a chat index, or write
response data to disk. Titles and UUIDs exist only in the running widget while
it displays them. Plasma stores only the widget's non-sensitive display
preferences and the allowlisted identifier of the preferred terminal emulator.
It never stores a terminal command or user-supplied executable path.

## Network and authentication

The addon does not implement its own network client or authentication flow. It
starts the existing Codex app-server through local standard input/output and
inherits the user's existing Codex configuration. Codex itself may communicate
with OpenAI according to that configuration and the applicable OpenAI terms.

The addon never opens app-server on TCP, WebSocket, or another network-facing
transport.

## New CLI and account actions

Starting a fresh chat launches the local Codex CLI without an automatic prompt.
If selected, the model, reasoning effort, sandbox mode, and approval policy are
passed as separate arguments. These are fixed official CLI values and do not
depend on shell functions or aliases. The addon does not read or edit Codex
configuration or credentials. Selecting the full approval-and-sandbox bypass
requires two button confirmations before the local process is started.

Using a limit reset requires two confirmations and sends a fresh idempotency
key to the documented app-server method. The backend selects the eligible
credit; the addon neither requests nor stores an opaque credit identifier.

## Telemetry

The addon contains no telemetry, advertising, crash-reporting, or analytics
code. This statement does not change analytics settings that may already apply
to the separately installed Codex CLI.

## Conversation actions

Renaming sends the validated UUID and normalized title to the documented
`thread/name/set` app-server method. Resuming validates the UUID and passes it
as a separate argument to `codex resume` inside a supported terminal process. That
resume action never supplies a prompt, model, sandbox, approval, or permission
override.
If the selected chat is archived, the explicit resume action first calls
`thread/unarchive`; listing or viewing it never changes archive state.
Permanently deleting an active or archived chat requires a separate
confirmation and sends only its validated UUID to `thread/delete`. The bulk
archive action first collects validated archived UUIDs, holds them in memory,
and sends them sequentially only after two button confirmations. The addon never
edits or removes Codex session files directly. Codex may also delete spawned
descendant threads as part of that documented operation.

Real titles, previews, UUIDs, and project paths must not be logged, included in
public screenshots, test fixtures, or source-control history.
