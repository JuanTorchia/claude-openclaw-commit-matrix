# Claude OpenClaw Commit Matrix

Reproducible PowerShell harness to test whether Claude Code executes `git commit`
commands whose commit message contains variants of `OpenClaw`.

The script runs against a clean real Git repository, creates a temporary worktree,
adds a small probe file, asks `claude` to run specific commit commands, and records
whether `HEAD` changed for each case.

## Usage

Run from PowerShell:

```powershell
.\Invoke-ClaudeCommitMatrix.ps1 -RepoPath "C:\path\to\clean\repo" -MaxBudgetUsd 1.00
```

Outputs are written to `claude-openclaw-lab-*` by default:

- `metadata.json`: repo, tool versions, branch, worktree, budget.
- `results.jsonl`: one machine-readable result per case.
- `summary.md`: compact table for publication.
- `*.claude.log`: raw Claude Code output per case.

## Safety Notes

- The input repository must have a clean `git status`.
- The script uses `git worktree` and does not push anything.
- The script calls `claude --dangerously-skip-permissions` inside the temporary
  worktree because the experiment is specifically about whether Claude Code runs
  the requested commit command.
- Running the script may consume Claude Code/API quota.
