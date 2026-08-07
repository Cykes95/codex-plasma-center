#!/usr/bin/env python3
"""Detect supported terminal emulators and build safe argument vectors."""

# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import shutil
from typing import Callable


TERMINALS = (
    {"id": "konsole", "displayName": "Konsole", "binary": "konsole"},
    {
        "id": "gnome-terminal",
        "displayName": "GNOME Terminal",
        "binary": "gnome-terminal",
    },
    {"id": "kitty", "displayName": "Kitty", "binary": "kitty"},
    {"id": "alacritty", "displayName": "Alacritty", "binary": "alacritty"},
    {"id": "wezterm", "displayName": "WezTerm", "binary": "wezterm"},
    {"id": "foot", "displayName": "Foot", "binary": "foot"},
    {"id": "xterm", "displayName": "XTerm", "binary": "xterm"},
)
TERMINALS_BY_ID = {terminal["id"]: terminal for terminal in TERMINALS}


class TerminalError(Exception):
    """A stable terminal selection error for the calling helper to map."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def detect_terminals(
    which: Callable[[str], str | None] = shutil.which,
) -> list[dict[str, str]]:
    detected: list[dict[str, str]] = []
    for terminal in TERMINALS:
        if which(terminal["binary"]) is not None:
            detected.append(
                {
                    "id": terminal["id"],
                    "displayName": terminal["displayName"],
                }
            )
    return detected


def resolve_terminal(
    terminal_id: str,
    which: Callable[[str], str | None] = shutil.which,
) -> tuple[str, str]:
    if terminal_id and terminal_id not in TERMINALS_BY_ID:
        raise TerminalError("invalid_terminal")

    candidates = (
        (TERMINALS_BY_ID[terminal_id],)
        if terminal_id
        else TERMINALS
    )
    for terminal in candidates:
        executable = which(terminal["binary"])
        if executable is not None:
            return terminal["id"], executable
    raise TerminalError("terminal_not_found")


def terminal_arguments(
    terminal_id: str,
    executable: str,
    working_directory: str,
    command: list[str],
) -> list[str]:
    if terminal_id not in TERMINALS_BY_ID or not command:
        raise TerminalError("invalid_terminal")

    if terminal_id == "konsole":
        return [
            executable,
            "--separate",
            "--workdir",
            working_directory,
            "-e",
            *command,
        ]
    if terminal_id == "gnome-terminal":
        return [
            executable,
            "--working-directory",
            working_directory,
            "--",
            *command,
        ]
    if terminal_id == "kitty":
        return [executable, "--directory", working_directory, *command]
    if terminal_id == "alacritty":
        return [
            executable,
            "--working-directory",
            working_directory,
            "-e",
            *command,
        ]
    if terminal_id == "wezterm":
        return [
            executable,
            "start",
            "--cwd",
            working_directory,
            "--",
            *command,
        ]
    if terminal_id == "foot":
        return [executable, "--working-directory", working_directory, *command]
    if terminal_id == "xterm":
        return [executable, "-e", *command]
    raise TerminalError("invalid_terminal")
