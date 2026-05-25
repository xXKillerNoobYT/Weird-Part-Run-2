import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class GitHubIssueSyncSourceIssueTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo_root = Path(__file__).resolve().parents[1]
        cls.script = cls.repo_root / "scripts" / "github-issue-sync.sh"

    def _run_sync(self, *, source_issue: str | None = None, paperclip_task_id: str | None = None):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            bin_dir = tmp_path / "bin"
            out_dir = tmp_path / "out"
            bin_dir.mkdir(parents=True, exist_ok=True)

            fake_gh = bin_dir / "gh"
            fake_gh.write_text(
                """#!/usr/bin/env bash
cat <<'JSON'
[
  {"number": 1, "title": "Open issue", "state": "OPEN", "labels": [], "assignees": [], "author": {"login": "bot"}, "createdAt": "2026-05-01T00:00:00Z", "updatedAt": "2026-05-03T00:00:00Z", "url": "https://github.com/example/repo/issues/1"},
  {"number": 2, "title": "Closed issue", "state": "CLOSED", "labels": [], "assignees": [], "author": {"login": "bot"}, "createdAt": "2026-05-02T00:00:00Z", "updatedAt": "2026-05-04T00:00:00Z", "url": "https://github.com/example/repo/issues/2"}
]
JSON
""",
                encoding="utf-8",
            )
            fake_gh.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            if paperclip_task_id is None:
                env.pop("PAPERCLIP_TASK_ID", None)
            else:
                env["PAPERCLIP_TASK_ID"] = paperclip_task_id

            command = [
                str(self.script),
                "--repo",
                "example/repo",
                "--output-dir",
                str(out_dir),
                "--state",
                "all",
            ]
            if source_issue is not None:
                command.extend(["--source-issue", source_issue])

            completed = subprocess.run(
                command,
                cwd=self.repo_root,
                env=env,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(
                completed.returncode,
                0,
                f"script failed:\nstdout:\n{completed.stdout}\nstderr:\n{completed.stderr}",
            )

            latest_md = (out_dir / "latest-sync.md").read_text(encoding="utf-8")
            latest_json = json.loads((out_dir / "latest-sync.json").read_text(encoding="utf-8"))
            return latest_md, latest_json

    def test_source_issue_flag_updates_latest_sync_artifacts(self):
        latest_md, latest_json = self._run_sync(source_issue="WEI-2309")

        self.assertIn("- Source issue: `WEI-2309`", latest_md)
        self.assertEqual(latest_json["sourceIssue"], "WEI-2309")

    def test_paperclip_task_id_is_used_when_flag_not_provided(self):
        latest_md, latest_json = self._run_sync(paperclip_task_id="WEI-9999")

        self.assertIn("- Source issue: `WEI-9999`", latest_md)
        self.assertEqual(latest_json["sourceIssue"], "WEI-9999")

    def test_default_source_issue_remains_backward_compatible(self):
        latest_md, latest_json = self._run_sync()

        self.assertIn("- Source issue: `WEI-44`", latest_md)
        self.assertEqual(latest_json["sourceIssue"], "WEI-44")


if __name__ == "__main__":
    unittest.main()
