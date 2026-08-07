# Contributing

Thank you for helping improve Codex Plasma Center.

## Ground rules

- Keep the project compatible with KDE Plasma 6.
- Use English for source strings and include translation context where useful.
- Do not include real account details, usage values, conversation names,
  prompts, machine paths, credentials, or identifiers in commits and fixtures.
- Do not read or write Codex internal session or credential files when the
  documented app-server protocol provides the capability.
- Do not copy code from unrelated Codex menu bar or Plasma projects.
- Keep commands fixed. Encode, quote, decode, and validate any dynamic value
  that must cross Plasma's executable data engine; pass subprocess values as
  separate arguments without a shell.
- Add tests for normalization and error handling when the protocol adapter
  changes.

## Before submitting a change

Run the available checks and inspect the full diff for private data:

```sh
python3 -m unittest discover -s tests -v
git diff --check
```

The Make target also validates QML, translations, XML, and whitespace.
