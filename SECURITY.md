# Security policy

## Supported versions

Codex Plasma Center has not published a stable release yet. Security fixes will
target the latest development version until the first release.

## Reporting a vulnerability

Please do not publish credentials, conversation contents, local paths, or
working exploits in a public issue. Once the public GitHub repository enables
private vulnerability reporting, use that channel. Until then, open a minimal
issue that contains no sensitive details and asks the maintainers for a private
contact path.

## Security boundaries

- The addon never asks for `sudo`, `pkexec`, or elevated filesystem access.
- It never reads or modifies Codex credential files directly.
- It communicates with app-server only through a child process on local
  standard input/output.
- The addon invokes documented account reads and narrowly scoped account and
  thread methods. Renaming, an explicit restore-before-resume action, confirmed
  permanent deletion, and a twice-confirmed limit reset are the persistent data
  mutations.
- Protocol data is reduced through explicit allowlists before QML receives it.
- Raw app-server stderr and unexpected fields are not returned to the widget.
- Missing values are treated as unavailable, not as trusted zero values.
- Thread IDs must parse as UUIDs, titles are normalized and bounded to 120
  characters, and opaque cursors are length-bounded.
- Individual `thread/delete` requires an explicit confirmation dialog that
  warns about permanent deletion of the selected thread and possible
  descendants.
- Bulk archive deletion requires two button confirmations. The helper collects and
  validates every archived UUID before deleting, rejects repeated cursors, and
  refuses batches over 1,000 entries. Since app-server has no atomic bulk
  method, a runtime failure can still leave partial completion and is reported
  as such.
- The helper never removes session files directly.
- Supported terminals and Codex are launched through an argument vector without a shell;
  the addon never appends an automatic prompt. Existing-chat resume does not
  change sandbox or approval settings.
- Fresh CLI sessions may receive a validated model, reasoning effort, sandbox
  mode, and approval policy. Values come from closed allowlists and are passed
  as separate arguments. The addon does not parse shell functions. The
  dangerous approval-and-sandbox bypass flag is isolated behind two button
  confirmations and cannot be combined with a separate approval value.
- A limit reset uses a UUID idempotency key and lets the backend choose the
  eligible credit, so opaque credit identifiers never reach QML.
- A saved working directory used for resume must be absolute and currently
  exist. It remains inside the helper and is never returned to QML.
- A newly selected working folder is length-bounded, must be an existing
  absolute directory, and is never persisted by the addon.
- Terminal selection accepts only a closed list of identifiers. The helper
  resolves the executable itself and never accepts an arbitrary command or
  executable path from QML or configuration. Automatic mode selects the first
  installed supported terminal.

Dynamic QML arguments are URI-encoded and shell-quoted before reaching the
fixed helper command. Helpers decode and validate them, then pass values to
app-server as JSON fields or to subprocesses as separate arguments.
