#!/usr/bin/env python3
"""List safe launcher choices and open a fresh Codex CLI session."""

# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Any
from urllib.parse import unquote

from codex_status import (
    AppServerClient,
    REQUEST_TIMEOUT_SECONDS,
    RequestUnavailable,
    StatusError,
)
from terminal_launcher import (
    TerminalError,
    detect_terminals,
    resolve_terminal,
    terminal_arguments,
)


SCHEMA_VERSION = 1
MAX_MODELS = 100
MAX_ARGUMENT_LENGTH = 128
MAX_ENCODED_ARGUMENT_LENGTH = 1024
MAX_WORKING_DIRECTORY_LENGTH = 4096
MAX_ENCODED_WORKING_DIRECTORY_LENGTH = 12288
MAX_CURSOR_LENGTH = 4096
SAFE_MODEL = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
SAFE_EFFORT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,31}\Z")
SANDBOX_MODES = {
    "",
    "read-only",
    "workspace-write",
    "danger-full-access",
    "dangerously-bypass-approvals-and-sandbox",
}
APPROVAL_POLICIES = {"", "untrusted", "on-request", "never"}


class LauncherError(StatusError):
    """An expected launcher failure exposed as a stable code."""


def decode_argument(value: str) -> str:
    if len(value) > MAX_ENCODED_ARGUMENT_LENGTH:
        raise LauncherError("invalid_input")
    try:
        decoded = unquote(value, encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, ValueError) as error:
        raise LauncherError("invalid_input") from error
    if "\x00" in decoded or len(decoded) > MAX_ARGUMENT_LENGTH:
        raise LauncherError("invalid_input")
    return decoded


def decode_working_directory_argument(value: str) -> str:
    if len(value) > MAX_ENCODED_WORKING_DIRECTORY_LENGTH:
        raise LauncherError("invalid_working_directory")
    try:
        decoded = unquote(value, encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, ValueError) as error:
        raise LauncherError("invalid_working_directory") from error
    if "\x00" in decoded or len(decoded) > MAX_WORKING_DIRECTORY_LENGTH:
        raise LauncherError("invalid_working_directory")
    return decoded


def resolve_working_directory(value: str) -> str:
    if not value:
        return str(Path.home().resolve())

    if value.startswith("file://"):
        try:
            value = unquote(
                value.removeprefix("file://"),
                encoding="utf-8",
                errors="strict",
            )
        except (UnicodeDecodeError, ValueError) as error:
            raise LauncherError("invalid_working_directory") from error
    candidate = Path(value)
    if not candidate.is_absolute():
        raise LauncherError("invalid_working_directory")
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise LauncherError("invalid_working_directory") from error
    if not resolved.is_dir():
        raise LauncherError("invalid_working_directory")
    return str(resolved)


def _safe_value(value: Any, pattern: re.Pattern[str]) -> str | None:
    return value if isinstance(value, str) and pattern.fullmatch(value) else None


def normalize_models(result: Any) -> list[dict[str, Any]]:
    values = result.get("data") if isinstance(result, dict) else None
    normalized: list[dict[str, Any]] = []
    if not isinstance(values, list):
        return normalized

    for value in values:
        if len(normalized) >= MAX_MODELS or not isinstance(value, dict):
            break
        model_id = _safe_value(value.get("model"), SAFE_MODEL)
        if model_id is None:
            continue
        display_name = value.get("displayName")
        if not isinstance(display_name, str) or not display_name.strip():
            display_name = model_id
        display_name = " ".join(display_name.split())[:80]

        efforts: list[str] = []
        raw_efforts = value.get("supportedReasoningEfforts")
        if isinstance(raw_efforts, list):
            for raw_effort in raw_efforts:
                effort = raw_effort.get("reasoningEffort") if isinstance(raw_effort, dict) else None
                effort = _safe_value(effort, SAFE_EFFORT)
                if effort is not None and effort not in efforts:
                    efforts.append(effort)

        default_effort = _safe_value(value.get("defaultReasoningEffort"), SAFE_EFFORT)
        if default_effort is not None and default_effort not in efforts:
            efforts.append(default_effort)
        normalized.append(
            {
                "id": model_id,
                "displayName": display_name,
                "isDefault": value.get("isDefault") is True,
                "defaultReasoningEffort": default_effort,
                "supportedReasoningEfforts": efforts,
            }
        )
    return normalized


def collect_launcher_options() -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise LauncherError("codex_not_found")

    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            result = client.request(
                "model/list",
                {"includeHidden": False, "limit": MAX_MODELS},
                REQUEST_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise LauncherError("models_unavailable") from error

    models = normalize_models(result)
    if not models:
        raise LauncherError("models_unavailable")
    models.sort(key=lambda item: (not item["isDefault"], item["displayName"].casefold()))
    return {"models": models, "terminals": detect_terminals()}


def validate_launch_selection(
    model: str,
    effort: str,
    sandbox_mode: str,
    approval_policy: str,
) -> None:
    if model and not SAFE_MODEL.fullmatch(model):
        raise LauncherError("invalid_input")
    if effort and (not model or not SAFE_EFFORT.fullmatch(effort)):
        raise LauncherError("invalid_input")
    if sandbox_mode not in SANDBOX_MODES or approval_policy not in APPROVAL_POLICIES:
        raise LauncherError("invalid_input")
    if sandbox_mode == "dangerously-bypass-approvals-and-sandbox" and approval_policy:
        raise LauncherError("invalid_input")


def launch_arguments(
    terminal_id: str,
    terminal_path: str,
    codex_path: str,
    working_directory: str,
    model: str,
    effort: str,
    sandbox_mode: str,
    approval_policy: str,
) -> list[str]:
    command = [codex_path]
    if model:
        command.extend(["--model", model])
    if effort:
        command.extend(["--config", f'model_reasoning_effort="{effort}"'])
    if sandbox_mode == "dangerously-bypass-approvals-and-sandbox":
        command.append("--dangerously-bypass-approvals-and-sandbox")
    elif sandbox_mode:
        command.extend(["--sandbox", sandbox_mode])
    if approval_policy:
        command.extend(["--ask-for-approval", approval_policy])
    command.extend(["-C", working_directory])
    return terminal_arguments(
        terminal_id,
        terminal_path,
        working_directory,
        command,
    )


def launch_codex(
    model: str,
    effort: str,
    sandbox_mode: str,
    approval_policy: str,
    selected_working_directory: str,
    selected_terminal: str,
) -> dict[str, bool]:
    validate_launch_selection(model, effort, sandbox_mode, approval_policy)
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise LauncherError("codex_not_found")
    working_directory = resolve_working_directory(selected_working_directory)
    try:
        terminal_id, terminal_path = resolve_terminal(selected_terminal)
    except TerminalError as error:
        raise LauncherError(error.code) from error

    try:
        subprocess.Popen(
            launch_arguments(
                terminal_id,
                terminal_path,
                codex_path,
                working_directory,
                model,
                effort,
                sandbox_mode,
                approval_policy,
            ),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=working_directory,
            close_fds=True,
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise LauncherError("launch_failed") from error
    return {"launched": True}


def success_payload(action: str, result: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "ok": True,
        "generatedAt": int(time.time()),
        "action": action,
        "result": result,
    }


def error_payload(action: str, code: str) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "ok": False,
        "generatedAt": int(time.time()),
        "action": action,
        "error": {"code": code},
    }


def execute(arguments: list[str]) -> tuple[dict[str, Any], int]:
    action = arguments[0] if arguments else "unknown"
    try:
        if action == "options" and len(arguments) == 1:
            result = collect_launcher_options()
        elif action == "launch" and len(arguments) == 7:
            model, effort, sandbox_mode, approval_policy = (
                decode_argument(value) for value in arguments[1:5]
            )
            working_directory = decode_working_directory_argument(arguments[5])
            selected_terminal = decode_argument(arguments[6])
            result = launch_codex(
                model,
                effort,
                sandbox_mode,
                approval_policy,
                working_directory,
                selected_terminal,
            )
        else:
            raise LauncherError("invalid_action")
        return success_payload(action, result), 0
    except StatusError as error:
        return error_payload(action, error.code), 1
    except Exception:
        return error_payload(action, "unexpected_error"), 1


def main() -> int:
    payload, exit_code = execute(sys.argv[1:])
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
