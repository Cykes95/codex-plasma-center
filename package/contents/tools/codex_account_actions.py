#!/usr/bin/env python3
"""Run narrowly scoped, explicitly confirmed Codex account actions."""

# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import shutil
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


SCHEMA_VERSION = 1
KNOWN_RESET_OUTCOMES = {
    "reset",
    "nothingToReset",
    "noCredit",
    "alreadyRedeemed",
}
MAX_ENCODED_ARGUMENT_LENGTH = 256


class AccountActionError(StatusError):
    """An expected account action failure exposed as a stable code."""


def decode_idempotency_key(value: str) -> str:
    if len(value) > MAX_ENCODED_ARGUMENT_LENGTH:
        raise AccountActionError("invalid_input")
    try:
        decoded = unquote(value, encoding="utf-8", errors="strict")
        return str(UUID(decoded))
    except (UnicodeDecodeError, ValueError, AttributeError, TypeError) as error:
        raise AccountActionError("invalid_input") from error


def normalize_reset_result(result: Any) -> dict[str, str]:
    outcome = result.get("outcome") if isinstance(result, dict) else None
    if outcome not in KNOWN_RESET_OUTCOMES:
        raise AccountActionError("invalid_protocol_response")
    return {"outcome": outcome}


def consume_reset_credit(idempotency_key: str) -> dict[str, str]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise AccountActionError("codex_not_found")

    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            result = client.request(
                "account/rateLimitResetCredit/consume",
                {"idempotencyKey": idempotency_key},
                REQUEST_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise AccountActionError("reset_unavailable") from error
    return normalize_reset_result(result)


def success_payload(action: str, result: dict[str, str]) -> dict[str, Any]:
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
        if action == "consume_reset" and len(arguments) == 2:
            idempotency_key = decode_idempotency_key(arguments[1])
            result = consume_reset_credit(idempotency_key)
        else:
            raise AccountActionError("invalid_action")
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
