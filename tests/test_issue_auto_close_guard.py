#!/usr/bin/env python3
"""Tests for scripts/issue-auto-close-guard.sh.

Verifies the three-check heuristic guard that prevents auto-closing
GitHub issues that are still actively tracked:

  Check A — issue number in Pending Questions section of docs/dev-qa.md
  Check B — issue number in docs/plans/*.md alongside a pending-status marker
  Check C — issue number in a QUEUED (🔲) row of xcode-ai/fix-prompts/00-fix-order.md
"""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
GUARD_SCRIPT = REPO_ROOT / "scripts" / "issue-auto-close-guard.sh"

# Exit codes emitted by the guard
EXIT_SAFE = 0
EXIT_SKIP = 1
EXIT_USAGE_ERROR = 2


def run_guard(issue_number: str | int, repo_root: str) -> tuple[int, str]:
    """Run the guard script and return (exit_code, combined_stdout_stderr)."""
    result = subprocess.run(
        [str(GUARD_SCRIPT), str(issue_number), repo_root],
        capture_output=True,
        text=True,
    )
    combined = result.stdout + result.stderr
    return result.returncode, combined


class GuardScriptExistenceTests(unittest.TestCase):
    def test_guard_script_exists(self):
        self.assertTrue(
            GUARD_SCRIPT.exists(),
            f"Guard script not found: {GUARD_SCRIPT}",
        )

    def test_guard_script_is_executable(self):
        self.assertTrue(
            os.access(GUARD_SCRIPT, os.X_OK),
            f"Guard script is not executable: {GUARD_SCRIPT}",
        )


class GuardUsageErrorTests(unittest.TestCase):
    def test_missing_issue_number_exits_with_usage_error(self):
        result = subprocess.run(
            [str(GUARD_SCRIPT)],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, EXIT_USAGE_ERROR)

    def test_non_integer_issue_number_exits_with_usage_error(self):
        code, _ = run_guard("notanumber", "/tmp")
        self.assertEqual(code, EXIT_USAGE_ERROR)

    def test_zero_issue_number_exits_with_usage_error(self):
        code, _ = run_guard("0", "/tmp")
        self.assertEqual(code, EXIT_USAGE_ERROR)

    def test_negative_issue_number_exits_with_usage_error(self):
        code, _ = run_guard("-5", "/tmp")
        self.assertEqual(code, EXIT_USAGE_ERROR)


class GuardCheckADevQaTests(unittest.TestCase):
    """Check A: issue number in Pending Questions section of docs/dev-qa.md."""

    def _make_repo(self, dev_qa_content: str) -> str:
        """Create a minimal fake repo root with a docs/dev-qa.md."""
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        (docs / "dev-qa.md").write_text(dev_qa_content, encoding="utf-8")
        (Path(tmpdir) / "docs" / "plans").mkdir()
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text("", encoding="utf-8")
        return tmpdir

    def test_issue_in_pending_section_triggers_skip(self):
        content = textwrap.dedent("""\
            ## Pending Questions

            ### Some Cluster

            1. Question about issue #221.
               > Answer: _pending_

            ## Answered Clusters
        """)
        repo = self._make_repo(content)
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check A", out)

    def test_issue_in_answered_section_does_not_trigger_skip(self):
        content = textwrap.dedent("""\
            ## Pending Questions

            _None. All clusters have been answered._

            ## Answered Clusters

            ### Some Old Cluster

            1. Question about issue #221 — already answered.
               > Answer: use Option B
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_none_sentinel_pending_section_is_safe(self):
        content = textwrap.dedent("""\
            ## Pending Questions

            _None. All clusters have been answered — see Answered Clusters below._

            ## Answered Clusters
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_issue_inside_html_comment_block_does_not_trigger(self):
        content = textwrap.dedent("""\
            ## Pending Questions

            _None._

            <!--
            ## Archived cluster with #221
            Question about #221 was resolved.
            -->

            ## Answered Clusters
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_different_issue_number_in_pending_does_not_trigger(self):
        content = textwrap.dedent("""\
            ## Pending Questions

            1. Question about issue #999.

            ## Answered Clusters
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_missing_dev_qa_file_is_safe(self):
        tmpdir = tempfile.mkdtemp()
        (Path(tmpdir) / "docs" / "plans").mkdir(parents=True)
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text("", encoding="utf-8")
        code, _ = run_guard(221, tmpdir)
        self.assertEqual(code, EXIT_SAFE)


class GuardCheckBPlansTests(unittest.TestCase):
    """Check B: issue in docs/plans/*.md alongside a pending-status marker."""

    def _make_repo(self, plan_files: dict[str, str]) -> str:
        """Create a fake repo with the given plan files."""
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        plans = docs / "plans"
        plans.mkdir()
        dev_qa = docs / "dev-qa.md"
        dev_qa.write_text(
            "## Pending Questions\n_None._\n## Answered Clusters\n",
            encoding="utf-8",
        )
        for name, content in plan_files.items():
            (plans / name).write_text(content, encoding="utf-8")
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text("", encoding="utf-8")
        return tmpdir

    def test_issue_in_plan_with_pending_marker_triggers_skip(self):
        repo = self._make_repo(
            {
                "sync-field-timestamps-upgrade.md": textwrap.dedent("""\
                    # Sync Field Timestamps Upgrade

                    Status: pending

                    Tracks issue #221.
                """)
            }
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check B", out)

    def test_issue_in_plan_with_not_yet_implemented_triggers_skip(self):
        repo = self._make_repo(
            {
                "some-plan.md": textwrap.dedent("""\
                    ## Phase 2 — Field Timestamps
                    Status: not yet implemented
                    See GitHub issue #221 for tracking.
                """)
            }
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check B", out)

    def test_issue_in_plan_with_implementation_pending_triggers_skip(self):
        repo = self._make_repo(
            {
                "another-plan.md": textwrap.dedent("""\
                    ## Phase 1 complete
                    ## Phase 2 — Implementation pending — #221
                """)
            }
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check B", out)

    def test_issue_in_plan_without_pending_marker_is_safe(self):
        repo = self._make_repo(
            {
                "done-plan.md": textwrap.dedent("""\
                    # Completed Plan
                    Issue #221 was resolved in commit abc123.
                    All phases complete.
                """)
            }
        )
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_different_issue_in_plan_with_pending_is_safe(self):
        repo = self._make_repo(
            {
                "other.md": textwrap.dedent("""\
                    Status: pending
                    See #999 for tracking.
                """)
            }
        )
        code, _ = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_missing_plans_dir_is_safe(self):
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        (docs / "dev-qa.md").write_text(
            "## Pending Questions\n_None._\n## Answered Clusters\n",
            encoding="utf-8",
        )
        # No docs/plans directory
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text("", encoding="utf-8")
        code, _ = run_guard(221, tmpdir)
        self.assertEqual(code, EXIT_SAFE)


class GuardCheckCXcodeQueueTests(unittest.TestCase):
    """Check C: issue in a QUEUED (🔲) row of xcode-ai/fix-prompts/00-fix-order.md."""

    def _make_repo(self, queue_content: str) -> str:
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        (docs / "dev-qa.md").write_text(
            "## Pending Questions\n_None._\n## Answered Clusters\n",
            encoding="utf-8",
        )
        (docs / "plans").mkdir()
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text(queue_content, encoding="utf-8")
        return tmpdir

    def test_queued_pe_entry_with_issue_triggers_skip(self):
        content = textwrap.dedent("""\
            ## Queue

            | # | File | What It Fixes | Status |
            |---|------|---------------|--------|
            | PE-051 | `PE-051-tools.md` | Dismiss guard tools. GitHub #143. | 🔲 NEXT |
        """)
        repo = self._make_repo(content)
        code, out = run_guard(143, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check C", out)

    def test_queued_to_be_written_pe_with_issue_triggers_skip(self):
        content = textwrap.dedent("""\
            ## Queue

            | PE-046 | *(to be written)* | CategoriesTreeView SKU rows. GitHub #237. | 🔲 PE-COLORS NEXT |
        """)
        repo = self._make_repo(content)
        code, out = run_guard(237, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check C", out)

    def test_done_pe_entry_with_issue_is_safe(self):
        content = textwrap.dedent("""\
            ## Queue

            | PE-044 | `PE-044.md` | Dismiss guard employees page. GitHub #143. | ✅ DONE 2026-04-15 |
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(143, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_archived_pe_entry_is_safe(self):
        content = textwrap.dedent("""\
            | PE-043 | *(archived)* | Photo picker. GitHub #152. | ✅ DONE 2026-04-15 |
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(152, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_issue_not_in_queue_is_safe(self):
        content = textwrap.dedent("""\
            ## Queue

            | PE-051 | `PE-051-tools.md` | GitHub #143. | 🔲 NEXT |
        """)
        repo = self._make_repo(content)
        code, _ = run_guard(999, repo)
        self.assertEqual(code, EXIT_SAFE)

    def test_missing_queue_file_is_safe(self):
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        (docs / "dev-qa.md").write_text(
            "## Pending Questions\n_None._\n## Answered Clusters\n",
            encoding="utf-8",
        )
        (docs / "plans").mkdir()
        # No xcode-ai/fix-prompts/00-fix-order.md
        code, _ = run_guard(221, tmpdir)
        self.assertEqual(code, EXIT_SAFE)


class GuardMultipleChecksTests(unittest.TestCase):
    """Guard correctly aggregates multiple triggered checks."""

    def _make_full_repo(
        self,
        dev_qa_content: str,
        plan_files: dict[str, str],
        queue_content: str,
    ) -> str:
        tmpdir = tempfile.mkdtemp()
        docs = Path(tmpdir) / "docs"
        docs.mkdir()
        (docs / "dev-qa.md").write_text(dev_qa_content, encoding="utf-8")
        plans = docs / "plans"
        plans.mkdir()
        for name, content in plan_files.items():
            (plans / name).write_text(content, encoding="utf-8")
        xcode = Path(tmpdir) / "xcode-ai" / "fix-prompts"
        xcode.mkdir(parents=True)
        (xcode / "00-fix-order.md").write_text(queue_content, encoding="utf-8")
        return tmpdir

    def test_all_three_checks_trigger_all_listed_in_output(self):
        repo = self._make_full_repo(
            dev_qa_content=textwrap.dedent("""\
                ## Pending Questions
                1. What to do about #221?
                   > Answer: _pending_
                ## Answered Clusters
            """),
            plan_files={
                "plan.md": "Status: pending\nRelated: #221\n",
            },
            queue_content="| PE-X | *(to be written)* | Do stuff. GitHub #221. | 🔲 NEXT |\n",
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("Check A", out)
        self.assertIn("Check B", out)
        self.assertIn("Check C", out)

    def test_no_checks_trigger_returns_safe(self):
        repo = self._make_full_repo(
            dev_qa_content="## Pending Questions\n_None._\n## Answered Clusters\n",
            plan_files={"done.md": "All phases complete. Issue #221 resolved.\n"},
            queue_content="| PE-X | *(done)* | GitHub #221. | ✅ DONE |\n",
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SAFE)
        self.assertIn("SAFE_TO_CLOSE", out)

    def test_output_includes_skip_auto_close_message_when_triggered(self):
        repo = self._make_full_repo(
            dev_qa_content=textwrap.dedent("""\
                ## Pending Questions
                1. Issue #221 — what to do?
                   > Answer: _pending_
                ## Answered Clusters
            """),
            plan_files={},
            queue_content="",
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("SKIP_AUTO_CLOSE", out)

    def test_output_includes_action_guidance_when_triggered(self):
        repo = self._make_full_repo(
            dev_qa_content="## Pending Questions\n1. #221\n## Answered Clusters\n",
            plan_files={},
            queue_content="",
        )
        code, out = run_guard(221, repo)
        self.assertEqual(code, EXIT_SKIP)
        self.assertIn("status-comment", out.lower())


class GuardLiveRepoSanityTests(unittest.TestCase):
    """Smoke-tests against the actual repository.

    These tests verify that the guard runs without error against the live
    docs in the repo. They do not assert specific guard outcomes (which
    depend on the ever-changing content of dev-qa.md / plans / queue),
    but they do assert that the script exits with a known code and
    produces non-empty output.
    """

    def test_guard_runs_against_live_repo_without_crashing(self):
        code, out = run_guard(221, str(REPO_ROOT))
        self.assertIn(code, (EXIT_SAFE, EXIT_SKIP), f"Unexpected exit code {code}: {out}")
        self.assertTrue(out.strip(), "Guard produced no output")

    def test_guard_produces_safe_or_skip_marker_in_output(self):
        code, out = run_guard(221, str(REPO_ROOT))
        self.assertTrue(
            "SAFE_TO_CLOSE" in out or "SKIP_AUTO_CLOSE" in out,
            f"Output missing SAFE_TO_CLOSE or SKIP_AUTO_CLOSE marker:\n{out}",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
