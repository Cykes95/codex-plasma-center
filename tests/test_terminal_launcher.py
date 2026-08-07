# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "package" / "contents" / "tools" / "terminal_launcher.py"
SPEC = importlib.util.spec_from_file_location("terminal_launcher", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
terminal_launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(terminal_launcher)


class TerminalLauncherTests(unittest.TestCase):
    @staticmethod
    def fake_which(binary: str) -> str | None:
        paths = {
            "alacritty": "/usr/bin/alacritty",
            "xterm": "/usr/bin/xterm",
        }
        return paths.get(binary)

    def test_detection_returns_only_available_allowlisted_terminals(self) -> None:
        self.assertEqual(
            terminal_launcher.detect_terminals(self.fake_which),
            [
                {"id": "alacritty", "displayName": "Alacritty"},
                {"id": "xterm", "displayName": "XTerm"},
            ],
        )

    def test_automatic_selection_falls_back_when_konsole_is_missing(self) -> None:
        self.assertEqual(
            terminal_launcher.resolve_terminal("", self.fake_which),
            ("alacritty", "/usr/bin/alacritty"),
        )

    def test_explicit_unavailable_or_unknown_terminal_is_rejected(self) -> None:
        with self.assertRaises(terminal_launcher.TerminalError) as unavailable:
            terminal_launcher.resolve_terminal("konsole", self.fake_which)
        self.assertEqual(unavailable.exception.code, "terminal_not_found")

        with self.assertRaises(terminal_launcher.TerminalError) as unknown:
            terminal_launcher.resolve_terminal("$(unsafe)", self.fake_which)
        self.assertEqual(unknown.exception.code, "invalid_terminal")

    def test_supported_terminal_argument_vectors_keep_command_separate(self) -> None:
        expected_prefixes = {
            "konsole": ["/terminal", "--separate", "--workdir", "/project", "-e"],
            "gnome-terminal": [
                "/terminal",
                "--working-directory",
                "/project",
                "--",
            ],
            "kitty": ["/terminal", "--directory", "/project"],
            "alacritty": [
                "/terminal",
                "--working-directory",
                "/project",
                "-e",
            ],
            "wezterm": [
                "/terminal",
                "start",
                "--cwd",
                "/project",
                "--",
            ],
            "foot": ["/terminal", "--working-directory", "/project"],
            "xterm": ["/terminal", "-e"],
        }
        command = ["/usr/bin/codex", "resume", "fictional-thread-id"]
        for terminal_id, prefix in expected_prefixes.items():
            with self.subTest(terminal_id=terminal_id):
                self.assertEqual(
                    terminal_launcher.terminal_arguments(
                        terminal_id,
                        "/terminal",
                        "/project",
                        command,
                    ),
                    prefix + command,
                )


if __name__ == "__main__":
    unittest.main()
