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

                if [[ "${FAKE_GH_LARGE_PAGINATED:-}" == "1" ]]; then
                  python3 - <<'PY'
                import json
                page1 = [
                    {
                        "number": number,
                        "title": f"Issue {number}",
                        "state": "open" if number % 2 else "closed",
                        "labels": [],
                        "assignees": [],
                        "user": {"login": "tester"},
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": f"2026-01-02T00:00:{number % 60:02d}Z",
                        "html_url": f"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/{number}",
                    }
                    for number in range(1, 151)
                ]
                page2 = [
                    {
                        "number": number,
                        "title": f"Issue {number}",
                        "state": "open" if number % 2 else "closed",
                        "labels": [],
                        "assignees": [],
                        "user": {"login": "tester"},
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": f"2026-01-03T00:00:{number % 60:02d}Z",
                        "html_url": f"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/{number}",
                    }
                    for number in range(151, 251)
                ]
                page2.append(
                    {
                        "number": 999,
                        "title": "Pull request should be filtered",
                        "state": "open",
                        "labels": [],
                        "assignees": [],
                        "user": {"login": "tester"},
                        "created_at": "2026-01-01T00:00:00Z",
                        "updated_at": "2026-01-04T00:00:00Z",
                        "html_url": "https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/999",
                        "pull_request": {"url": "https://api.github.com/repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/999"},
                    }
                )
                json.dump([page1, page2], __import__("sys").stdout)
                PY
                  exit 0
                fi

                cat <<'JSON'
                [
                  {"number":752,"title":"Sync metadata bug","state":"open","labels":[],"assignees":[],"user":{"login":"tester"},"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z","html_url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/752"},
                  {"number":900,"title":"Pull request should be filtered","state":"open","labels":[],"assignees":[],"user":{"login":"tester"},"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-03T00:00:00Z","html_url":"https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/900","pull_request":{"url":"https://api.github.com/repos/xXKillerNoobYT/Weird-Part-Run-2/pulls/900"}}
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

    def test_paginated_api_sync_keeps_more_than_200_non_pr_issues(self):
        out_dir = self.run_sync("--state", "all", env={"FAKE_GH_LARGE_PAGINATED": "1"})
        latest_json = json.loads((out_dir / "latest-sync.json").read_text(encoding="utf-8"))

        self.assertEqual(latest_json["issueCount"], 250)
        self.assertEqual(latest_json["openCount"], 125)
        self.assertEqual(latest_json["closedCount"], 125)
        self.assertNotIn(999, {issue["number"] for issue in latest_json["issues"]})
        self.assertEqual(latest_json["issues"][0]["state"], "OPEN")


if __name__ == "__main__":
    unittest.main()
