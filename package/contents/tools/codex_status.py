#!/usr/bin/env python3
"""Return a privacy-reduced Codex account status snapshot as JSON."""

# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import json
import os
import re
import select
import shutil
import subprocess
import sys
import time
from typing import Any


SCHEMA_VERSION = 1
CLIENT_VERSION = "0.7.0"
INITIALIZE_TIMEOUT_SECONDS = 8.0
REQUEST_TIMEOUT_SECONDS = 12.0
SAFE_IDENTIFIER = re.compile(r"[^A-Za-z0-9._-]+")


class StatusError(Exception):
    """An expected failure that is safe to expose as a stable error code."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class RequestUnavailable(Exception):
    """A non-fatal app-server request failure."""


def _bounded_number(value: Any, minimum: float, maximum: float) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    numeric = float(value)
    if numeric < minimum or numeric > maximum:
        return None
    return numeric


def _bounded_integer(value: Any, minimum: int, maximum: int) -> int | None:
    numeric = _bounded_number(value, minimum, maximum)
    if numeric is None or not numeric.is_integer():
        return None
    return int(numeric)


def _safe_identifier(value: Any, fallback: str) -> str:
    if not isinstance(value, str):
        return fallback
    normalized = SAFE_IDENTIFIER.sub("-", value.strip())[:64].strip("-")
    return normalized or fallback


def normalize_account(result: Any) -> dict[str, Any]:
    """Allowlist non-identifying account fields."""

    result_map = result if isinstance(result, dict) else {}
    account = result_map.get("account")
    if not isinstance(account, dict):
        return {
            "authenticated": False,
            "authType": None,
            "plan": None,
        }

    auth_type = account.get("type")
    plan = account.get("planType")
    return {
        "authenticated": True,
        "authType": _safe_identifier(auth_type, "unknown"),
        "plan": _safe_identifier(plan, "unknown") if plan else None,
    }


def normalize_window(window: Any) -> dict[str, Any] | None:
    if not isinstance(window, dict):
        return None

    used_percent = _bounded_number(window.get("usedPercent"), 0.0, 100.0)
    duration_minutes = _bounded_integer(
        window.get("windowDurationMins"), 1, 525_600
    )
    resets_at = _bounded_integer(window.get("resetsAt"), 0, 4_102_444_800)

    if used_percent is None and duration_minutes is None and resets_at is None:
        return None

    return {
        "usedPercent": used_percent,
        "remainingPercent": round(100.0 - used_percent, 2)
        if used_percent is not None
        else None,
        "windowDurationMins": duration_minutes,
        "resetsAt": resets_at,
    }


def normalize_rate_limits(result: Any) -> dict[str, Any]:
    """Allowlist rate-limit windows and omit opaque account/service details."""

    if not isinstance(result, dict):
        return {
            "available": False,
            "items": [],
            "resetCreditsAvailable": None,
        }

    snapshots: list[Any] = []
    by_id = result.get("rateLimitsByLimitId")
    if isinstance(by_id, dict) and by_id:
        snapshots.extend(by_id.values())
    elif isinstance(result.get("rateLimits"), dict):
        snapshots.append(result["rateLimits"])

    items: list[dict[str, Any]] = []
    for index, snapshot in enumerate(snapshots):
        if not isinstance(snapshot, dict):
            continue
        primary = normalize_window(snapshot.get("primary"))
        secondary = normalize_window(snapshot.get("secondary"))
        if primary is None and secondary is None:
            continue
        items.append(
            {
                "id": _safe_identifier(snapshot.get("limitId"), f"limit-{index + 1}"),
                "primary": primary,
                "secondary": secondary,
            }
        )

    reset_credits = result.get("rateLimitResetCredits")
    available_count = None
    if isinstance(reset_credits, dict):
        available_count = _bounded_integer(
            reset_credits.get("availableCount"), 0, 1_000_000
        )

    return {
        "available": bool(items),
        "items": items,
        "resetCreditsAvailable": available_count,
    }


def normalize_usage(result: Any) -> dict[str, Any]:
    """Allowlist aggregate metrics and omit daily activity buckets."""

    summary = result.get("summary") if isinstance(result, dict) else None
    if not isinstance(summary, dict):
        return {"available": False, "summary": {}}

    allowed_fields = (
        "lifetimeTokens",
        "peakDailyTokens",
        "longestRunningTurnSec",
        "currentStreakDays",
        "longestStreakDays",
    )
    normalized: dict[str, int] = {}
    for field in allowed_fields:
        value = _bounded_integer(summary.get(field), 0, 10**18)
        if value is not None:
            normalized[field] = value

    return {"available": bool(normalized), "summary": normalized}


class AppServerClient:
    def __init__(self, codex_path: str):
        try:
            self.process = subprocess.Popen(
                [codex_path, "app-server", "--stdio"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                encoding="utf-8",
                bufsize=1,
                cwd=os.path.abspath(os.sep),
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise StatusError("app_server_start_failed") from error

        if self.process.stdin is None or self.process.stdout is None:
            self.close()
            raise StatusError("app_server_start_failed")

        self._next_id = 1

    def _send(self, message: dict[str, Any]) -> None:
        if self.process.poll() is not None:
            raise StatusError("app_server_stopped")
        try:
            assert self.process.stdin is not None
            self.process.stdin.write(
                json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n"
            )
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise StatusError("app_server_stopped") from error

    def _read_response(self, request_id: int, timeout: float) -> dict[str, Any]:
        deadline = time.monotonic() + timeout
        assert self.process.stdout is not None

        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise StatusError("app_server_timeout")

            readable, _, _ = select.select([self.process.stdout], [], [], remaining)
            if not readable:
                raise StatusError("app_server_timeout")

            line = self.process.stdout.readline()
            if line == "":
                raise StatusError("app_server_stopped")

            try:
                message = json.loads(line)
            except json.JSONDecodeError as error:
                raise StatusError("invalid_protocol_response") from error

            if not isinstance(message, dict) or message.get("id") != request_id:
                continue
            if "error" in message:
                raise RequestUnavailable
            result = message.get("result")
            return result if isinstance(result, dict) else {}

    def request(self, method: str, params: Any, timeout: float) -> dict[str, Any]:
        request_id = self._next_id
        self._next_id += 1
        message: dict[str, Any] = {"method": method, "id": request_id}
        if params is not None:
            message["params"] = params
        self._send(message)
        return self._read_response(request_id, timeout)

    def initialize(self) -> None:
        try:
            self.request(
                "initialize",
                {
                    "clientInfo": {
                        "name": "codex_plasma_center",
                        "title": "Codex Plasma Center",
                        "version": CLIENT_VERSION,
                    }
                },
                INITIALIZE_TIMEOUT_SECONDS,
            )
        except RequestUnavailable as error:
            raise StatusError("incompatible_app_server") from error
        self._send({"method": "initialized", "params": {}})

    def close(self) -> None:
        process = getattr(self, "process", None)
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=1.0)

    def __enter__(self) -> "AppServerClient":
        return self

    def __exit__(self, _type: Any, _value: Any, _traceback: Any) -> None:
        self.close()


def read_codex_version(codex_path: str) -> str | None:
    try:
        completed = subprocess.run(
            [codex_path, "--version"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            timeout=3.0,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None

    match = re.search(r"\b([0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9.-]+)?)\b", completed.stdout)
    return match.group(1) if match else None


def _unavailable_section() -> dict[str, Any]:
    return {
        "available": False,
        "items": [],
        "resetCreditsAvailable": None,
    }


def collect_status() -> dict[str, Any]:
    codex_path = shutil.which("codex")
    if codex_path is None:
        raise StatusError("codex_not_found")

    codex_version = read_codex_version(codex_path)
    with AppServerClient(codex_path) as client:
        client.initialize()
        try:
            account_result = client.request(
                "account/read", {"refreshToken": False}, REQUEST_TIMEOUT_SECONDS
            )
        except RequestUnavailable as error:
            raise StatusError("account_unavailable") from error

        account = normalize_account(account_result)
        rate_limits = _unavailable_section()
        usage: dict[str, Any] = {"available": False, "summary": {}}

        auth_type = account.get("authType")
        supports_service_usage = account["authenticated"] and auth_type not in {
            "apiKey",
            "amazonBedrock",
        }

        if supports_service_usage:
            try:
                rate_limits = normalize_rate_limits(
                    client.request(
                        "account/rateLimits/read", None, REQUEST_TIMEOUT_SECONDS
                    )
                )
            except RequestUnavailable:
                pass

            try:
                usage = normalize_usage(
                    client.request("account/usage/read", None, REQUEST_TIMEOUT_SECONDS)
                )
            except RequestUnavailable:
                pass

    return {
        "schemaVersion": SCHEMA_VERSION,
        "ok": True,
        "generatedAt": int(time.time()),
        "codexVersion": codex_version,
        "account": account,
        "rateLimits": rate_limits,
        "usage": usage,
    }


def error_payload(code: str) -> dict[str, Any]:
    return {
        "schemaVersion": SCHEMA_VERSION,
        "ok": False,
        "generatedAt": int(time.time()),
        "error": {"code": code},
    }


def main() -> int:
    try:
        payload = collect_status()
        exit_code = 0
    except StatusError as error:
        payload = error_payload(error.code)
        exit_code = 1
    except Exception:
        payload = error_payload("unexpected_error")
        exit_code = 1

    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
