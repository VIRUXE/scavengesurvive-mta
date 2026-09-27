from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_github_planning_files_exist():
    for name in [".github/ISSUE_TEMPLATE/port-task.yml", ".github/ISSUE_TEMPLATE/bug.yml",
                 ".github/ISSUE_TEMPLATE/research.yml", ".github/ISSUE_TEMPLATE/config.yml",
                 "CODEOWNERS", "SECURITY.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", "docs/PROJECT_README.md"]:
        assert (ROOT / name).is_file(), name


def test_no_ci_workflows():
    # Project rule: no CI. Checks run locally (tools/setup-dev.ps1); commits go straight to main.
    assert not (ROOT / ".github/workflows").exists()
    assert not (ROOT / ".github/rulesets").exists()
