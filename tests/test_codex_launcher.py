# SPDX-FileCopyrightText: 2026 Codex Plasma Center contributors
# SPDX-License-Identifier: MIT

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
TOOLS_PATH = ROOT / "package" / "contents" / "tools"
sys.path.insert(0, str(TOOLS_PATH))
HELPER_PATH = TOOLS_PATH / "codex_launcher.py"
SPEC = importlib.util.spec_from_file_location("codex_launcher", HELPER_PATH)
assert SPEC is not None and SPEC.loader is not None
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def test_models_are_reduced_to_picker_fields(self) -> None:
        normalized = launcher.normalize_models(
            {
                "data": [
                    {
                        "id": "gpt-fictional",
                        "model": "gpt-fictional",
                        "displayName": "Fictional model",
                        "description": "discarded",
                        "isDefault": True,
                        "defaultReasoningEffort": "medium",
                        "supportedReasoningEfforts": [
                            {"reasoningEffort": "low", "description": "discarded"},
                            {"reasoningEffort": "medium", "description": "discarded"},
                        ],
                        "privateField": "discarded",
                    }
                ]
            }
        )
        self.assertEqual(
            normalized,
            [
                {
                    "id": "gpt-fictional",
                    "displayName": "Fictional model",
                    "isDefault": True,
                    "defaultReasoningEffort": "medium",
                    "supportedReasoningEfforts": ["low", "medium"],
                }
            ],
        )

    def test_launch_arguments_never_use_a_shell(self) -> None:
        self.assertEqual(
            launcher.launch_arguments(
                "konsole",
                "/usr/bin/konsole",
                "/usr/bin/codex",
                "/fictional/project with spaces",
                "gpt-fictional",
                "high",
                "workspace-write",
                "on-request",
            ),
            [
                "/usr/bin/konsole",
                "--separate",
                "--workdir",
                "/fictional/project with spaces",
                "-e",
                "/usr/bin/codex",
                "--model",
                "gpt-fictional",
                "--config",
                'model_reasoning_effort="high"',
                "--sandbox",
                "workspace-write",
                "--ask-for-approval",
                "on-request",
                "-C",
                "/fictional/project with spaces",
            ],
        )

    def test_effort_requires_an_explicit_model(self) -> None:
        with self.assertRaises(launcher.LauncherError) as context:
            launcher.validate_launch_selection("", "high", "", "")
        self.assertEqual(context.exception.code, "invalid_input")

    def test_unknown_permission_values_are_rejected(self) -> None:
        with self.assertRaises(launcher.LauncherError) as context:
            launcher.validate_launch_selection(
                "gpt-fictional", "high", "unsafe-value", ""
            )
        self.assertEqual(context.exception.code, "invalid_input")

    def test_bypass_uses_exact_official_flag(self) -> None:
        arguments = launcher.launch_arguments(
            "konsole",
            "/usr/bin/konsole",
            "/usr/bin/codex",
            "/fictional/project with spaces",
            "",
            "",
            "dangerously-bypass-approvals-and-sandbox",
            "",
        )
        self.assertIn("--dangerously-bypass-approvals-and-sandbox", arguments)
        self.assertNotIn("--sandbox", arguments)
        self.assertNotIn("--ask-for-approval", arguments)

    def test_bypass_rejects_separate_approval_policy(self) -> None:
        with self.assertRaises(launcher.LauncherError) as context:
            launcher.validate_launch_selection(
                "",
                "",
                "dangerously-bypass-approvals-and-sandbox",
                "never",
            )
        self.assertEqual(context.exception.code, "invalid_input")

    def test_empty_working_directory_uses_current_home_default(self) -> None:
        self.assertEqual(
            launcher.resolve_working_directory(""),
            str(Path.home().resolve()),
        )

    def test_existing_folder_with_spaces_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fictional project ") as directory:
            self.assertEqual(
                launcher.resolve_working_directory(directory),
                str(Path(directory).resolve()),
            )

    def test_file_url_is_accepted_for_existing_folder(self) -> None:
        with tempfile.TemporaryDirectory(prefix="fictional project ") as directory:
            folder_url = Path(directory).as_uri()
            self.assertEqual(
                launcher.resolve_working_directory(folder_url),
                str(Path(directory).resolve()),
            )

    def test_relative_or_missing_working_directory_is_rejected(self) -> None:
        for directory in ("relative/project", "/fictional/missing/project"):
            with self.subTest(directory=directory):
                with self.assertRaises(launcher.LauncherError) as context:
                    launcher.resolve_working_directory(directory)
                self.assertEqual(
                    context.exception.code,
                    "invalid_working_directory",
                )

    def test_regular_file_cannot_be_a_working_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "fictional.txt"
            file_path.touch()
            with self.assertRaises(launcher.LauncherError) as context:
                launcher.resolve_working_directory(str(file_path))
            self.assertEqual(context.exception.code, "invalid_working_directory")


if __name__ == "__main__":
    unittest.main()
