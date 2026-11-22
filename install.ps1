<#
.SYNOPSIS
Sets up the overseer skill on this machine.

.DESCRIPTION
Installs multiplexer-driver (required) and overseer (optional) into
%USERPROFILE%\.local\bin, clones the skill into your agent's skills
directory, and writes the example profile file if there is none.
overseer-judge is installed only on request. Each binary has its own
installer, published with its release. This script runs those
installers in turn, then prints the versions and the next steps.

.PARAMETER WithJudge
Also install overseer-judge. It needs a TypeSafe API key, and it sends
pane, task, and review text to that API.

.PARAMETER NoLaunch
Skip overseer, the session launcher, and the profile file.

.PARAMETER NoSkill
Skip the skill clone.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File install.ps1 -WithJudge
#>
param(
    [switch]$WithJudge,
    [switch]$NoLaunch,
    [switch]$NoSkill
)

$ErrorActionPreference = 'Stop'

if (-not $NoSkill -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required to clone the skill (-NoSkill skips it)'
}

# Runs the release installer of the GitHub project photuris/<Repo>, in
# a child process and with the exact command its README documents.
function Install-Tool([string]$Repo) {
    Write-Host "==> $Repo"

    $url = "https://github.com/photuris/$Repo/releases/latest/download/$Repo-installer.ps1"
    powershell -ExecutionPolicy Bypass -c "irm $url | iex"

    if ($LASTEXITCODE -ne 0) {
        throw "the $Repo installer failed with exit code $LASTEXITCODE"
    }
}

# Prints the version of a binary. A new binary may not be on PATH in
# this session yet, so the install directory is tried first.
function Show-Version([string]$Name) {
    $installed = Join-Path $HOME ".local\bin\$Name.exe"

    if (Test-Path $installed) {
        & $installed --version
    } elseif (Get-Command $Name -ErrorAction SilentlyContinue) {
        & $Name --version
    } else {
        throw "$Name was not found after its installer ran"
    }
}

# Returns the skills directories to install into: Codex's when Codex is
# present, Claude Code's when Claude Code is present or when neither
# agent was found.
function Get-SkillDirs {
    $dirs = @()

    if ((Get-Command codex -ErrorAction SilentlyContinue) -or
        (Test-Path (Join-Path $HOME '.codex'))) {
        $dirs += Join-Path $HOME '.agents\skills'
    }

    if ($dirs.Count -eq 0 -or
        (Get-Command claude -ErrorAction SilentlyContinue) -or
        (Test-Path (Join-Path $HOME '.claude'))) {
        $dirs += Join-Path $HOME '.claude\skills'
    }

    return $dirs
}

# Clones the skill into a skills directory. A path that already exists
# (a clone, a link to a checkout, a copy) is never changed.
function Install-Skill([string]$Dir) {
    $dest = Join-Path $Dir 'overseer'

    if (Test-Path $dest) {
        Write-Host "$dest already exists, left as it is"
        Write-Host "  (update a clone with: git -C $dest pull)"
        return
    }

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    git clone --quiet --depth 1 https://github.com/photuris/overseer $dest

    if ($LASTEXITCODE -ne 0) {
        throw "git clone into $dest failed with exit code $LASTEXITCODE"
    }

    Write-Host $dest
}

Install-Tool 'multiplexer-driver'
if (-not $NoLaunch) { Install-Tool 'overseer-launch' }
if ($WithJudge) { Install-Tool 'overseer-judge' }

if (-not $NoSkill) {
    Write-Host '==> skill'
    foreach ($dir in Get-SkillDirs) { Install-Skill $dir }
}

# The launcher's default location (its `default_path`). `overseer init`
# refuses to replace a file, so it runs only when there is none.
$profiles = Join-Path $env:APPDATA 'overseer\profiles.toml'

if (-not $NoLaunch) {
    Write-Host '==> profiles'

    if (Test-Path $profiles) {
        Write-Host "$profiles already exists, left as it is"
    } else {
        & (Join-Path $HOME '.local\bin\overseer.exe') init | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw "overseer init failed with exit code $LASTEXITCODE"
        }

        Write-Host $profiles
    }
}

Write-Host '==> installed'
Show-Version 'multiplexer-driver'
if (-not $NoLaunch) { Show-Version 'overseer' }
if ($WithJudge) { Show-Version 'overseer-judge' }

# The allow rules name the harness. The Herdr desktop app sets a
# variable in every terminal; anything else is taken to be Herdr.
$harness = if ($env:HC_TERMINAL_ID) { 'hc' } else { 'herdr' }

Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Open a new terminal if an installer added %USERPROFILE%\.local\bin to your PATH.'
if (-not $NoLaunch) {
    Write-Host "  2. Edit ${profiles}: keep the agent commands you have."
    Write-Host '  3. Inside a Herdr pane, run: overseer'
} else {
    Write-Host '  2. Set OVERSEER_IMPLEMENTER and OVERSEER_REVIEWER, then start your agent'
    Write-Host '     inside a Herdr pane.'
}
Write-Host ''
Write-Host 'If the overseer runs as Claude Code in auto mode, add these to'
Write-Host 'permissions.allow in ~/.claude/settings.json before the first run:'
Write-Host "  `"Bash(multiplexer-driver --harness $harness pane spawn:*)`","
Write-Host "  `"Bash(multiplexer-driver --harness $harness pane split:*)`""
