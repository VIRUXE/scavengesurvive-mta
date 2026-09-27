import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REQUIRED_CHECKS = {"luacheck", "stylua", "busted", "tools", "sql", "docs"}


def _ci_job_ids():
    text = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    jobs = text.split("\njobs:\n", 1)[1]
    return set(re.findall(r"^  ([a-z][a-z0-9_-]*):\s*$", jobs, re.M))


def test_github_files_exist():
    for name in [".github/workflows/ci.yml", ".github/workflows/release.yml", ".github/workflows/labeler.yml",
                 ".github/labeler.yml", ".github/release.yml", ".github/dependabot.yml",
                 ".github/ISSUE_TEMPLATE/port-task.yml", ".github/ISSUE_TEMPLATE/bug.yml",
                 ".github/ISSUE_TEMPLATE/research.yml", ".github/ISSUE_TEMPLATE/config.yml",
                 ".github/PULL_REQUEST_TEMPLATE.md", "CODEOWNERS", "SECURITY.md", "CONTRIBUTING.md",
                 "CODE_OF_CONDUCT.md", ".markdownlint.jsonc", "lychee.toml", "docs/PROJECT_README.md"]:
        assert (ROOT / name).is_file(), name


def test_ci_jobs_match_required_checks():
    assert _ci_job_ids() == REQUIRED_CHECKS


def test_ruleset_requires_every_ci_job_and_blocks_force_push():
    rs = json.loads((ROOT / ".github/rulesets/main.json").read_text(encoding="utf-8"))
    rules = {r["type"]: r for r in rs["rules"]}
    ctx = {c["context"] for c in rules["required_status_checks"]["parameters"]["required_status_checks"]}
    assert ctx == REQUIRED_CHECKS
    assert {"pull_request", "non_fast_forward", "deletion"} <= rules.keys()
    assert rs["conditions"]["ref_name"]["include"] == ["refs/heads/main"]


def test_sql_job_enables_event_scheduler():
    assert "event_scheduler" in (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
