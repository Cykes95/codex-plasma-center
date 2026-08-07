#!/usr/bin/env python3
"""List, rename, delete, and resume Codex threads through narrow operations."""

# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from typing import Any
from urllib.parse import unquote
from uuid import UUID

from codex_status import (
    AppServerClient,
    REQUEST_TIMEOUT_SECONDS,
    RequestUnavailable,
    StatusError,
)
from terminal_launcher import (
    TerminalError,
    resolve_terminal,
    terminal_arguments,
)


SCHEMA_VERSION = 1
PAGE_SIZE = 20
MAX_TITLE_LENGTH = 120
MAX_SEARCH_LENGTH = 120
MAX_CURSOR_LENGTH = 4096
MAX_ENCODED_ARGUMENT_LENGTH = 8192
MAX_BULK_DELETE_THREADS = 1000
INTERACTIVE_SOURCES = ["cli", "vscode", "appServer"]
KNOWN_STATUSES = {"notLoaded", "idle", "systemError", "active"}
WHITESPACE = re.compile(r"\s+")


class ThreadsError(StatusError):
    """An expected thread operation failure exposed as a stable code."""


def decode_argument(value: str, maximum_length: int) -> str:
    if len(value) > MAX_ENCODED_ARGUMENT_LENGTH:
        raise ThreadsError("invalid_input")
    try:
        decoded = unquote(value, encoding="utf-8", errors="strict")
    except (UnicodeDecodeError, ValueError) as error:
        raise ThreadsError("invalid_input") from error
    if "\x00" in decoded or len(decoded) > maximum_length:
        raise ThreadsError("invalid_input")
    return decoded


def normalize_text(value: Any, maximum_length: int = MAX_TITLE_LENGTH) -> str:
    if not isinstance(value, str):
        return ""
    normalized = WHITESPACE.sub(" ", value).strip()
    return normalized[:maximum_length]


def normalize_title(value: str) -> str:
    title = normalize_text(value)
    if not title:
        raise ThreadsError("invalid_title")
    return title


def validate_thread_id(value: str) -> str:
    try:
        parsed = UUID(value)
    except (ValueError, AttributeError, TypeError) as error:
        raise ThreadsError("invalid_thread_id") from error
    return str(parsed)


def bounded_timestamp(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    if value < 0 or value > 4_102_444_800:
        return None
    return value


def normalize_status(value: Any) -> str:
    if not isinstance(value, dict):
        return "unknown"
    status = value.get("type")
    return status if status in KNOWN_STATUSES else "unknown"


def normalize_thread(value: Any, archived: bool = False) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    try:
        thread_id = validate_thread_id(value.get("id"))
    except ThreadsError:
        return None

    name = normalize_text(value.get("name"))
    preview = normalize_text(value.get("preview"))
    return {
        "id": thread_id,
        "title": name or preview,
        "hasCustomName": bool(name),
        "updatedAt": bounded_timestamp(value.get("updatedAt")),
        "status": normalize_status(value.get("status")),
        "archived": archived,
    }


def normalize_thread_list(result: Any, archived: bool = False) -> dict[str, Any]:
    result_map = result if isinstance(result, dict) else {}
    values = result_map.get("data")
    items: list[dict[str, Any]] = []
    if isinstance(values, list):
        for value in values[:PAGE_SIZE]:
            normalized = normalize_thread(value, archived)
            if normalized is not None:
                items.append(normalized)

    next_cursor = result_map.get("nextCursor")
    if not isinstance(next_cursor, str) or len(next_cursor) > MAX_CURSOR_LENGTH:
        next_cursor = None

    return {"items": items, "nextCursor": next_cursor}


def list_params(
    cursor: str | None,
    search_term: str,
    archived: bool,
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "limit": PAGE_SIZE,
        "sortKey": "updated_at",
        "sortDirection": "desc",
        "sourceKinds": INTERACTIVE_SOURCES,
        "archived": archived,
    }
    if cursor:
        params["cursor"] = cursor
    if search_term:
        params["searchTerm"] = search_term
    return params


def decode_page_cursor(cursor: str) -> tuple[bool, str | None, str | None]:
    if not cursor:
        return True, None, None
    try:
        value = json.loads(cursor)
    except json.JSONDecodeError as error:
        raise ThreadsError("invalid_input") from error
    if not isinstance(value, dict) or set(value) != {"active", "archived"}:
        raise ThreadsError("invalid_input")

    active = value.get("active")
    archived = value.get("archived")
    for item in (active, archived):
        if item is not None and (
            not isinstance(item, str) or len(item) > MAX_CURSOR_LENGTH
        ):
            raise ThreadsError("invalid_input")
    return False, active, archived


def encode_page_cursor(active: str | None, archived: str | None) -> str | None:
    if active is None and archived is None:
        return None
    return json.dumps(
        {"active": active, "archived": archived},
        ensure_ascii=True,
        separators=(",", ":"),
    )


def list_threads(cursor: str, search_term: str) -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise ThreadsError("codex_not_found")

    initial_page, active_cursor, archived_cursor = decode_page_cursor(cursor)
    items: list[dict[str, Any]] = []
    next_active = None
    next_archived = None

    with AppServerClient(codex_path) as client:
        client.initialize()
        if initial_page or active_cursor is not None:
            try:
                active_result = client.request(
                    "thread/list",
                    list_params(active_cursor, search_term, False),
                    REQUEST_TIMEOUT_SECONDS,
                )
            except RequestUnavailable as error:
                raise ThreadsError("threads_unavailable") from error
            active_page = normalize_thread_list(active_result, False)
            items.extend(active_page["items"])
            next_active = active_page["nextCursor"]

        if initial_page or archived_cursor is not None:
            try:
                archived_result = client.request(
                    "thread/list",
                    list_params(archived_cursor, search_term, True),
                    REQUEST_TIMEOUT_SECONDS,
                )
            except RequestUnavailable as error:
                raise ThreadsError("threads_unavailable") from error
            archived_page = normalize_thread_list(archived_result, True)
            items.extend(archived_page["items"])
            next_archived = archived_page["nextCursor"]

    items.sort(key=lambda item: item.get("updatedAt") or 0, reverse=True)
    return {
        "items": items,
        "nextCursor": encode_page_cursor(next_active, next_archived),
    }


def rename_thread(thread_id: str, title: str) -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise ThreadsError("codex_not_found")

    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            client.request(
                "thread/name/set",
                {"threadId": thread_id, "name": title},
                REQUEST_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise ThreadsError("rename_failed") from error

    return {"threadId": thread_id, "title": title}


def delete_thread(thread_id: str) -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise ThreadsError("codex_not_found")

    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            client.request(
                "thread/delete",
                {"threadId": thread_id},
                REQUEST_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise ThreadsError("delete_failed") from error

    return {"threadId": thread_id}


def collect_archived_thread_ids(client: AppServerClient) -> list[str]:
    thread_ids: list[str] = []
    known_ids: set[str] = set()
    known_cursors: set[str] = set()
    cursor: str | None = None

    while True:
        try:
            result = client.request(
                "thread/list",
                list_params(cursor, "", True),
                REQUEST_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise ThreadsError("bulk_delete_failed") from error

        result_map = result if isinstance(result, dict) else {}
        values = result_map.get("data")
        if not isinstance(values, list) or len(values) > PAGE_SIZE:
            raise ThreadsError("bulk_delete_failed")

        for value in values:
            if not isinstance(value, dict):
                raise ThreadsError("bulk_delete_failed")
            try:
                thread_id = validate_thread_id(value.get("id"))
            except ThreadsError as error:
                raise ThreadsError("bulk_delete_failed") from error
            if thread_id not in known_ids:
                known_ids.add(thread_id)
                thread_ids.append(thread_id)
                if len(thread_ids) > MAX_BULK_DELETE_THREADS:
                    raise ThreadsError("bulk_delete_too_large")

        next_cursor = result_map.get("nextCursor")
        if next_cursor is None:
            return thread_ids
        if (
            not isinstance(next_cursor, str)
            or not next_cursor
            or len(next_cursor) > MAX_CURSOR_LENGTH
            or next_cursor in known_cursors
        ):
            raise ThreadsError("bulk_delete_failed")
        known_cursors.add(next_cursor)
        cursor = next_cursor


def delete_all_archived_threads() -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise ThreadsError("codex_not_found")

    with AppServerClient(codex_path) as client:
        client.initialize()
        thread_ids = collect_archived_thread_ids(client)

        for thread_id in thread_ids:
            try:
                client.request(
                    "thread/delete",
                    {"threadId": thread_id},
                    REQUEST_TIMEOUT_SECONDS,
                )
            except RequestUnavailable as error:
                raise ThreadsError("bulk_delete_partial") from error

    return {"deletedCount": len(thread_ids)}


def extract_thread_cwd(result: Any) -> str | None:
    thread = result.get("thread") if isinstance(result, dict) else None
    cwd = thread.get("cwd") if isinstance(thread, dict) else None
    if not isinstance(cwd, str) or not os.path.isabs(cwd) or not os.path.isdir(cwd):
        return None
    return os.path.abspath(cwd)


def resume_arguments(
    terminal_id: str,
    terminal_path: str,
    codex_path: str,
    thread_id: str,
    thread_cwd: str | None,
) -> list[str]:
    working_directory = thread_cwd or os.path.abspath(os.sep)
    command = [codex_path, "resume"]
    if thread_cwd is not None:
        command.extend(["-C", thread_cwd])
    command.append(thread_id)
    return terminal_arguments(
        terminal_id,
        terminal_path,
        working_directory,
        command,
    )


def resume_thread(
    thread_id: str,
    archived: bool,
    selected_terminal: str,
) -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise ThreadsError("codex_not_found")
    try:
        terminal_id, terminal_path = resolve_terminal(selected_terminal)
    except TerminalError as error:
        raise ThreadsError(error.code) from error

    thread_cwd = None
    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            if archived:
                thread_result = client.request(
                    "thread/unarchive",
                    {"threadId": thread_id},
                    REQUEST_TIMEOUT_SECONDS,
                )
            else:
                thread_result = client.request(
                    "thread/read",
                    {"threadId": thread_id, "includeTurns": False},
                    REQUEST_TIMEOUT_SECONDS,
                )
        except RequestUnavailable as error:
            raise ThreadsError("resume_failed") from error
        thread_cwd = extract_thread_cwd(thread_result)

    try:
        subprocess.Popen(
            resume_arguments(
                terminal_id,
                terminal_path,
                codex_path,
                thread_id,
                thread_cwd,
            ),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=thread_cwd or os.path.abspath(os.sep),
            close_fds=True,
            start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise ThreadsError("resume_failed") from error

    return {"threadId": thread_id, "unarchived": archived}


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
        if action == "list" and len(arguments) == 3:
            cursor = decode_argument(arguments[1], MAX_CURSOR_LENGTH)
            search_term = normalize_text(
                decode_argument(arguments[2], MAX_SEARCH_LENGTH),
                MAX_SEARCH_LENGTH,
            )
            result = list_threads(cursor, search_term)
        elif action == "rename" and len(arguments) == 3:
            thread_id = validate_thread_id(
                decode_argument(arguments[1], MAX_TITLE_LENGTH)
            )
            title = normalize_title(
                decode_argument(arguments[2], MAX_TITLE_LENGTH)
            )
            result = rename_thread(thread_id, title)
        elif action == "delete" and len(arguments) == 2:
            thread_id = validate_thread_id(
                decode_argument(arguments[1], MAX_TITLE_LENGTH)
            )
            result = delete_thread(thread_id)
        elif action == "delete_archived_all" and len(arguments) == 1:
            result = delete_all_archived_threads()
        elif action == "resume" and len(arguments) == 4:
            thread_id = validate_thread_id(
                decode_argument(arguments[1], MAX_TITLE_LENGTH)
            )
            archived_value = decode_argument(arguments[2], 1)
            if archived_value not in {"0", "1"}:
                raise ThreadsError("invalid_input")
            selected_terminal = decode_argument(arguments[3], 32)
            result = resume_thread(
                thread_id,
                archived_value == "1",
                selected_terminal,
            )
        else:
            raise ThreadsError("invalid_action")
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
