# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "package" / "contents" / "tools" / "codex_status.py"
SPEC = importlib.util.spec_from_file_location("codex_status", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
codex_status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(codex_status)


class NormalizationTests(unittest.TestCase):
    def test_account_discards_identifying_fields(self) -> None:
        normalized = codex_status.normalize_account(
            {
                "account": {
                    "type": "chatgpt",
                    "email": "alex@example.invalid",
                    "accountId": "account-private-example",
                    "planType": "plus",
                },
                "requiresOpenaiAuth": True,
            }
        )

        self.assertEqual(
            normalized,
            {"authenticated": True, "authType": "chatgpt", "plan": "plus"},
        )
        serialized = json.dumps(normalized)
        self.assertNotIn("alex", serialized)
        self.assertNotIn("account-private-example", serialized)

    def test_missing_account_is_not_authenticated(self) -> None:
        self.assertEqual(
            codex_status.normalize_account({"account": None}),
            {"authenticated": False, "authType": None, "plan": None},
        )

    def test_rate_limits_keep_only_display_metrics(self) -> None:
        normalized = codex_status.normalize_rate_limits(
            {
                "rateLimitsByLimitId": {
                    "codex": {
                        "limitId": "codex",
                        "limitName": "Private workspace label",
                        "primary": {
                            "usedPercent": 25,
                            "windowDurationMins": 300,
                            "resetsAt": 2_000_000_000,
                        },
                        "secondary": None,
                        "credits": {"balance": "private-value"},
                    }
                },
                "rateLimitResetCredits": {
                    "availableCount": 2,
                    "credits": [{"id": "opaque-private-credit-id"}],
                },
            }
        )

        self.assertTrue(normalized["available"])
        self.assertEqual(normalized["items"][0]["id"], "codex")
        self.assertEqual(normalized["items"][0]["primary"]["remainingPercent"], 75.0)
        self.assertEqual(normalized["resetCreditsAvailable"], 2)
        serialized = json.dumps(normalized)
        self.assertNotIn("Private workspace", serialized)
        self.assertNotIn("opaque-private-credit-id", serialized)
        self.assertNotIn("private-value", serialized)

    def test_invalid_percent_is_unavailable_not_zero(self) -> None:
        normalized = codex_status.normalize_window(
            {"usedPercent": 150, "windowDurationMins": 300, "resetsAt": None}
        )
        assert normalized is not None
        self.assertIsNone(normalized["usedPercent"])
        self.assertIsNone(normalized["remainingPercent"])

    def test_usage_omits_daily_buckets_and_unknown_fields(self) -> None:
        normalized = codex_status.normalize_usage(
            {
                "summary": {
                    "lifetimeTokens": 123_456,
                    "currentStreakDays": 4,
                    "privateMetric": 99,
                },
                "dailyUsageBuckets": [
                    {"startDate": "2030-01-01", "tokens": 12_345}
                ],
            }
        )

        self.assertEqual(
            normalized,
            {
                "available": True,
                "summary": {"lifetimeTokens": 123_456, "currentStreakDays": 4},
            },
        )
        serialized = json.dumps(normalized)
        self.assertNotIn("2030-01-01", serialized)
        self.assertNotIn("privateMetric", serialized)

    def test_error_payload_exposes_only_stable_code(self) -> None:
        payload = codex_status.error_payload("app_server_timeout")
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], {"code": "app_server_timeout"})


if __name__ == "__main__":
    unittest.main()
