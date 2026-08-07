# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
TOOLS_PATH = ROOT / "package" / "contents" / "tools"
sys.path.insert(0, str(TOOLS_PATH))
HELPER_PATH = TOOLS_PATH / "codex_threads.py"
SPEC = importlib.util.spec_from_file_location("codex_threads", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
codex_threads = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(codex_threads)


THREAD_ID = "019c0000-0000-7000-8000-000000000001"
THREAD_ID_2 = "019c0000-0000-7000-8000-000000000002"


class ThreadHelperTests(unittest.TestCase):
    def test_list_allowlist_discards_paths_turns_and_unknown_fields(self) -> None:
        normalized = codex_threads.normalize_thread_list(
            {
                "data": [
                    {
                        "id": THREAD_ID,
                        "name": "Fictional device audit",
                        "preview": "A fictional prompt",
                        "cwd": "/fictional/example/project",
                        "turns": [{"content": "fictional transcript"}],
                        "updatedAt": 2_000_000_000,
                        "status": {"type": "idle", "secret": "value"},
                        "unknown": "private field",
                    }
                ],
                "nextCursor": "opaque-example-cursor",
                "backwardsCursor": "discarded-cursor",
            }
        )

        self.assertEqual(
            normalized,
            {
                "items": [
                    {
                        "id": THREAD_ID,
                        "title": "Fictional device audit",
                        "hasCustomName": True,
                        "updatedAt": 2_000_000_000,
                        "status": "idle",
                        "archived": False,
                    }
                ],
                "nextCursor": "opaque-example-cursor",
            },
        )
        serialized = json.dumps(normalized)
        self.assertNotIn("/fictional/example", serialized)
        self.assertNotIn("fictional transcript", serialized)
        self.assertNotIn("private field", serialized)
        self.assertNotIn("A fictional prompt", serialized)

    def test_preview_is_used_only_when_no_custom_name_exists(self) -> None:
        normalized = codex_threads.normalize_thread(
            {
                "id": THREAD_ID,
                "name": None,
                "preview": "  Example   conversation\n",
                "updatedAt": 2_000_000_000,
                "status": {"type": "notLoaded"},
            }
        )
        assert normalized is not None
        self.assertEqual(normalized["title"], "Example conversation")
        self.assertFalse(normalized["hasCustomName"])
        self.assertFalse(normalized["archived"])

    def test_invalid_thread_id_is_rejected(self) -> None:
        with self.assertRaises(codex_threads.ThreadsError) as context:
            codex_threads.validate_thread_id("$(touch unsafe)")
        self.assertEqual(context.exception.code, "invalid_thread_id")

    def test_title_is_trimmed_collapsed_and_bounded(self) -> None:
        title = codex_threads.normalize_title("  Example\n\tname  " + "x" * 200)
        self.assertTrue(title.startswith("Example name"))
        self.assertEqual(len(title), codex_threads.MAX_TITLE_LENGTH)

    def test_list_params_include_only_interactive_sources(self) -> None:
        self.assertEqual(
            codex_threads.list_params("cursor", "term", True),
            {
                "limit": 20,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "sourceKinds": ["cli", "vscode", "appServer"],
                "archived": True,
                "cursor": "cursor",
                "searchTerm": "term",
            },
        )

    def test_combined_cursor_round_trip(self) -> None:
        encoded = codex_threads.encode_page_cursor("active-cursor", "archive-cursor")
        assert encoded is not None
        self.assertEqual(
            codex_threads.decode_page_cursor(encoded),
            (False, "active-cursor", "archive-cursor"),
        )

    def test_archived_thread_is_marked(self) -> None:
        normalized = codex_threads.normalize_thread(
            {
                "id": THREAD_ID,
                "preview": "Archived example",
                "updatedAt": 2_000_000_000,
                "status": {"type": "notLoaded"},
            },
            archived=True,
        )
        assert normalized is not None
        self.assertTrue(normalized["archived"])

    def test_delete_uses_app_server_with_validated_thread_id(self) -> None:
        requests: list[tuple[str, dict[str, str], float]] = []

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
                self,
                method: str,
                params: dict[str, str],
                timeout: float,
            ) -> dict[str, object]:
                requests.append((method, params, timeout))
                return {}

        with (
            mock.patch.object(
                codex_threads.shutil, "which", return_value="/usr/bin/codex"
            ),
            mock.patch.object(
                codex_threads, "AppServerClient", FakeAppServerClient
            ),
        ):
            result = codex_threads.delete_thread(THREAD_ID)

        self.assertEqual(result, {"threadId": THREAD_ID})
        self.assertEqual(
            requests,
            [
                (
                    "thread/delete",
                    {"threadId": THREAD_ID},
                    codex_threads.REQUEST_TIMEOUT_SECONDS,
                )
            ],
        )

    def test_delete_action_rejects_an_invalid_thread_id(self) -> None:
        payload, exit_code = codex_threads.execute(["delete", "not-a-uuid"])
        self.assertEqual(exit_code, 1)
        self.assertEqual(payload["error"], {"code": "invalid_thread_id"})

    def test_bulk_delete_collects_all_pages_before_deleting(self) -> None:
        methods: list[str] = []
        list_calls = 0

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
                self,
                method: str,
                params: dict[str, object],
                timeout: float,
            ) -> dict[str, object]:
                nonlocal list_calls
                methods.append(method)
                if method == "thread/list":
                    list_calls += 1
                    if list_calls == 1:
                        return {
                            "data": [{"id": THREAD_ID}],
                            "nextCursor": "fictional-next-page",
                        }
                    return {"data": [{"id": THREAD_ID_2}], "nextCursor": None}
                return {}

        with (
            mock.patch.object(
                codex_threads.shutil, "which", return_value="/usr/bin/codex"
            ),
            mock.patch.object(
                codex_threads, "AppServerClient", FakeAppServerClient
            ),
        ):
            result = codex_threads.delete_all_archived_threads()

        self.assertEqual(result, {"deletedCount": 2})
        self.assertEqual(
            methods,
            ["thread/list", "thread/list", "thread/delete", "thread/delete"],
        )

    def test_bulk_delete_rejects_a_repeated_cursor_before_deleting(self) -> None:
        methods: list[str] = []

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
                self,
                method: str,
                params: dict[str, object],
                timeout: float,
            ) -> dict[str, object]:
                methods.append(method)
                return {
                    "data": [{"id": THREAD_ID}],
                    "nextCursor": "repeated-cursor",
                }

        with (
            mock.patch.object(
                codex_threads.shutil, "which", return_value="/usr/bin/codex"
            ),
            mock.patch.object(
                codex_threads, "AppServerClient", FakeAppServerClient
            ),
        ):
            with self.assertRaises(codex_threads.ThreadsError) as context:
                codex_threads.delete_all_archived_threads()

        self.assertEqual(context.exception.code, "bulk_delete_failed")
        self.assertEqual(methods, ["thread/list", "thread/list"])

    def test_resume_uses_separate_argument_vector(self) -> None:
        self.assertEqual(
            codex_threads.resume_arguments(
                "konsole",
                "/usr/bin/konsole",
                "/usr/bin/codex",
                THREAD_ID,
                None,
            ),
            [
                "/usr/bin/konsole",
                "--separate",
                "--workdir",
                "/",
                "-e",
                "/usr/bin/codex",
                "resume",
                THREAD_ID,
            ],
        )

    def test_resume_with_cwd_keeps_path_in_separate_arguments(self) -> None:
        self.assertEqual(
            codex_threads.resume_arguments(
                "konsole",
                "/usr/bin/konsole",
                "/usr/bin/codex",
                THREAD_ID,
                "/fictional/project",
            ),
            [
                "/usr/bin/konsole",
                "--separate",
                "--workdir",
                "/fictional/project",
                "-e",
                "/usr/bin/codex",
                "resume",
                "-C",
                "/fictional/project",
                THREAD_ID,
            ],
        )

    def test_extract_thread_cwd_rejects_non_absolute_path(self) -> None:
        self.assertIsNone(
            codex_threads.extract_thread_cwd(
                {"thread": {"cwd": "relative/project", "turns": ["discarded"]}}
            )
        )

    def test_error_payload_does_not_expose_exception_details(self) -> None:
        payload = codex_threads.error_payload("rename", "rename_failed")
        self.assertEqual(payload["error"], {"code": "rename_failed"})
        self.assertNotIn("message", json.dumps(payload))


if __name__ == "__main__":
    unittest.main()
