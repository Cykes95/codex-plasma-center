# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock
from uuid import UUID


ROOT = Path(__file__).resolve().parents[1]
TOOLS_PATH = ROOT / "package" / "contents" / "tools"
sys.path.insert(0, str(TOOLS_PATH))
HELPER_PATH = TOOLS_PATH / "codex_account_actions.py"
SPEC = importlib.util.spec_from_file_location("codex_account_actions", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
account_actions = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(account_actions)


class AccountActionTests(unittest.TestCase):
    def test_consume_reset_uses_only_idempotency_key(self) -> None:
        requests: list[tuple[str, dict[str, str], float]] = []
        key = "019c0000-0000-7000-8000-000000000010"

        class FakeAppServerClient:
            def __init__(self, codex_path: str) -> None:
                self.codex_path = codex_path

            def __enter__(self) -> "FakeAppServerClient":
                return self

            def __exit__(self, *args: object) -> None:
                return None

            def initialize(self) -> None:
                return None

            def request(
                self, method: str, params: dict[str, str], timeout: float
            ) -> dict[str, str]:
                requests.append((method, params, timeout))
                return {"outcome": "reset"}

        with (
            mock.patch.object(account_actions.shutil, "which", return_value="/usr/bin/codex"),
            mock.patch.object(account_actions, "AppServerClient", FakeAppServerClient),
        ):
            result = account_actions.consume_reset_credit(key)

        self.assertEqual(result, {"outcome": "reset"})
        self.assertEqual(
            requests,
            [
                (
                    "account/rateLimitResetCredit/consume",
                    {"idempotencyKey": key},
                    account_actions.REQUEST_TIMEOUT_SECONDS,
                )
            ],
        )
        self.assertNotIn("creditId", requests[0][1])

    def test_idempotency_key_must_be_a_uuid(self) -> None:
        with self.assertRaises(account_actions.AccountActionError):
            account_actions.decode_idempotency_key("not-a-uuid")
        self.assertEqual(
            str(UUID("019c0000-0000-7000-8000-000000000010")),
            account_actions.decode_idempotency_key(
                "019c0000-0000-7000-8000-000000000010"
            ),
        )

    def test_unknown_reset_outcome_is_rejected(self) -> None:
        with self.assertRaises(account_actions.AccountActionError) as context:
            account_actions.normalize_reset_result({"outcome": "fictional"})
        self.assertEqual(context.exception.code, "invalid_protocol_response")


if __name__ == "__main__":
    unittest.main()
