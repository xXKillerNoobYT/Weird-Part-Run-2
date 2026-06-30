#!/usr/bin/env python3
from __future__ import annotations

"""Regression tests for scripts/github-issue-sync.sh source metadata."""

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SYNC_SCRIPT = REPO_ROOT / "scripts" / "github-issue-sync.sh"


class GitHubIssueSyncSourceIssueTests(unittest.TestCase):
    def run_sync(self, *args: str, env: dict[str, str] | None = None) -> Path:
        tmpdir_handle = tempfile.TemporaryDirectory()
        self.addCleanup(tmpdir_handle.cleanup)
        tmpdir = Path(tmpdir_handle.name)
        bin_dir = tmpdir / "bin"
        out_dir = tmpdir / "out"
        bin_dir.mkdir()
        fake_gh = bin_dir / "gh"
        fake_gh.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env bash
                set -euo pipefail
                cat <<'JSON'
                [
                  {"number":752,"title":"Sync metadata bug","state":"OPEN","labels":[],"assignees":[],"author":{"login":"tester"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/752"},
                  {"number":900,"title":"Pull request should be filtered","state":"OPEN","labels":[],"assignees":[],"author":{"login":"tester"},"createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-03T00:00:00Z","url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/900"}
                ]
                JSON
                """
            ),
            encoding="utf-8",
        )
        fake_gh.chmod(0o755)

        run_env = os.environ.copy()
        run_env.update(env or {})
        run_env["PATH"] = f"{bin_dir}:{run_env['PATH']}"

        result = subprocess.run(
            [str(SYNC_SCRIPT), "--repo", "xXKillerNoobYT/Weird-Part-Run-2", "--output-dir", str(out_dir), *args],
            cwd=REPO_ROOT,
            env=run_env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return out_dir

    def test_source_issue_option_updates_markdown_and_json(self):
        out_dir = self.run_sync("--state", "all", "--source-issue", "WEI-4159")

        latest_md = (out_dir / "latest-sync.md").read_text(encoding="utf-8")
        latest_json = json.loads((out_dir / "latest-sync.json").read_text(encoding="utf-8"))

        self.assertIn("- Source issue: `WEI-4159`", latest_md)
        self.assertEqual(latest_json["sourceIssue"], "WEI-4159")
        self.assertEqual(latest_json["issueCount"], 1)

    def test_paperclip_task_id_defaults_source_issue(self):
        out_dir = self.run_sync("--state", "open", env={"PAPERCLIP_TASK_ID": "WEI-4160"})
        latest_json = json.loads((out_dir / "latest-sync.json").read_text(encoding="utf-8"))
        self.assertEqual(latest_json["sourceIssue"], "WEI-4160")

    def test_legacy_default_preserves_existing_callers(self):
        out_dir = self.run_sync("--state", "closed", env={"PAPERCLIP_TASK_ID": ""})
        latest_md = (out_dir / "latest-sync.md").read_text(encoding="utf-8")
        latest_json = json.loads((out_dir / "latest-sync.json").read_text(encoding="utf-8"))

        self.assertIn("- Source issue: `WEI-44`", latest_md)
        self.assertEqual(latest_json["sourceIssue"], "WEI-44")


if __name__ == "__main__":
    unittest.main()
