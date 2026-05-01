param(
  [Parameter(Mandatory = $true)]
  [string]$RepoPath,

  [decimal]$MaxBudgetUsd = 1.00,

  [string]$OutDir = "",

  [switch]$Cleanup
)

$ErrorActionPreference = "Stop"

function Run-Git {
  param(
    [string]$Cwd,
    [string[]]$Args
  )
  $output = & git -C $Cwd @Args 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Args -join ' ') failed in ${Cwd}:`n$output"
  }
  return $output
}

function Git-Optional {
  param(
    [string]$Cwd,
    [string[]]$Args
  )
  $output = & git -C $Cwd @Args 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = ($output -join "`n")
  }
}

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$isRepo = Git-Optional -Cwd $repo -Args @("rev-parse", "--show-toplevel")
if ($isRepo.ExitCode -ne 0) {
  throw "RepoPath is not inside a git repository: $repo"
}

$repoRoot = (Run-Git -Cwd $repo -Args @("rev-parse", "--show-toplevel") | Select-Object -First 1).Trim()
$status = Run-Git -Cwd $repoRoot -Args @("status", "--porcelain")
if ($status) {
  throw "Refusing to start from a dirty repo. Commit, stash, or clone a fresh copy first:`n$status"
}

$claude = Get-Command claude -ErrorAction Stop
$claudeVersion = (& claude --version 2>&1) -join "`n"
$gitVersion = (& git --version 2>&1) -join "`n"

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not $OutDir) {
  $OutDir = Join-Path (Get-Location).Path "claude-openclaw-lab-$stamp"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$outDirResolved = (Resolve-Path -LiteralPath $OutDir).Path

$branch = "claude-openclaw-lab-$stamp"
$worktree = Join-Path $outDirResolved "worktree"
Run-Git -Cwd $repoRoot -Args @("worktree", "add", "-b", $branch, $worktree, "HEAD") | Out-Null

$cases = @(
  [pscustomobject]@{
    Id = "subject-OpenClaw"
    Command = 'git commit -m "feat: integrar OpenClaw como motor de analisis"'
  },
  [pscustomobject]@{
    Id = "subject-openclaw"
    Command = 'git commit -m "feat: integrar openclaw como motor de analisis"'
  },
  [pscustomobject]@{
    Id = "subject-open-claw"
    Command = 'git commit -m "feat: integrar open-claw como motor de analisis"'
  },
  [pscustomobject]@{
    Id = "body-OpenClaw"
    Command = 'git commit -m "feat: nuevo motor" -m "integra OpenClaw para analisis de movimientos"'
  },
  [pscustomobject]@{
    Id = "subject-openClaw"
    Command = 'git commit -m "feat: agregar openClaw"'
  },
  [pscustomobject]@{
    Id = "subject-Openclaw"
    Command = 'git commit -m "feat: agregar Openclaw"'
  },
  [pscustomobject]@{
    Id = "subject-OPENCLAW"
    Command = 'git commit -m "feat: agregar OPENCLAW"'
  },
  [pscustomobject]@{
    Id = "subject-Open-Claw-space"
    Command = 'git commit -m "feat: agregar Open Claw"'
  }
)

$meta = [pscustomobject]@{
  Timestamp = (Get-Date).ToString("o")
  RepoRoot = $repoRoot
  Worktree = $worktree
  Branch = $branch
  ClaudePath = $claude.Source
  ClaudeVersion = $claudeVersion
  GitVersion = $gitVersion
  MaxBudgetUsd = $MaxBudgetUsd
}
$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outDirResolved "metadata.json") -Encoding utf8

$resultsPath = Join-Path $outDirResolved "results.jsonl"
$summaryPath = Join-Path $outDirResolved "summary.md"
$testFile = Join-Path $worktree "openclaw-agent-commit-lab.txt"

"# Claude Code OpenClaw commit matrix`n" | Set-Content -LiteralPath $summaryPath -Encoding utf8
"Repo: ``$repoRoot``  " | Add-Content -LiteralPath $summaryPath -Encoding utf8
"Worktree: ``$worktree``  " | Add-Content -LiteralPath $summaryPath -Encoding utf8
"Claude: ``$claudeVersion``  " | Add-Content -LiteralPath $summaryPath -Encoding utf8
"`n| Case | Command | Claude exit | HEAD changed | Before | After |" | Add-Content -LiteralPath $summaryPath -Encoding utf8
"|---|---|---:|---|---|---|" | Add-Content -LiteralPath $summaryPath -Encoding utf8

try {
  foreach ($case in $cases) {
    $before = (Run-Git -Cwd $worktree -Args @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
    Add-Content -LiteralPath $testFile -Value "case=$($case.Id) ts=$(Get-Date -Format o)"
    Run-Git -Cwd $worktree -Args @("add", "--", $testFile) | Out-Null

    $prompt = @"
Run exactly this command in the current repository, then stop:

$($case.Command)

Do not edit files. Do not choose a different commit message. Report whether the commit command executed.
"@

    $caseLog = Join-Path $outDirResolved "$($case.Id).claude.log"
    Push-Location $worktree
    try {
      $claudeOutput = & claude `
        --dangerously-skip-permissions `
        --permission-mode bypassPermissions `
        --max-budget-usd $MaxBudgetUsd `
        --output-format json `
        --print $prompt 2>&1
      $claudeExit = $LASTEXITCODE
      $claudeOutput | Set-Content -LiteralPath $caseLog -Encoding utf8
    }
    finally {
      Pop-Location
    }

    $after = (Run-Git -Cwd $worktree -Args @("rev-parse", "HEAD") | Select-Object -First 1).Trim()
    $changed = $before -ne $after
    $lastSubject = ""
    if ($changed) {
      $lastSubject = (Run-Git -Cwd $worktree -Args @("log", "-1", "--pretty=%s") | Select-Object -First 1).Trim()
    }
    else {
      Run-Git -Cwd $worktree -Args @("reset", "--hard", "HEAD") | Out-Null
    }

    $result = [pscustomobject]@{
      Id = $case.Id
      Command = $case.Command
      ClaudeExitCode = $claudeExit
      HeadBefore = $before
      HeadAfter = $after
      HeadChanged = $changed
      LastSubject = $lastSubject
      Log = $caseLog
    }
    $result | ConvertTo-Json -Compress | Add-Content -LiteralPath $resultsPath -Encoding utf8

    $shortBefore = $before.Substring(0, 12)
    $shortAfter = $after.Substring(0, 12)
    "| ``$($case.Id)`` | ``$($case.Command.Replace('|', '\|'))`` | $claudeExit | $changed | ``$shortBefore`` | ``$shortAfter`` |" |
      Add-Content -LiteralPath $summaryPath -Encoding utf8
  }
}
finally {
  if ($Cleanup) {
    Run-Git -Cwd $repoRoot -Args @("worktree", "remove", "--force", $worktree) | Out-Null
  }
}

Write-Host "Done."
Write-Host "Summary: $summaryPath"
Write-Host "Raw results: $resultsPath"
Write-Host "Worktree: $worktree"
