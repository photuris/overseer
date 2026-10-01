<#
.SYNOPSIS
Installs the overseer skill's companion binaries from their latest
GitHub releases.

.DESCRIPTION
Installs multiplexer-driver (required), overseer-judge (optional), and
overseer (optional) into %USERPROFILE%\.local\bin. Each binary has its
own installer, published with its release. This script only runs those
installers in turn, then prints the versions.

It does not install the skill itself: clone this repository into your
agent's skills directory for that (see README.md).

.PARAMETER NoJudge
Skip overseer-judge.

.PARAMETER NoLaunch
Skip overseer, the session launcher.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File install.ps1 -NoJudge
#>
param(
    [switch]$NoJudge,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

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

Install-Tool 'multiplexer-driver'
if (-not $NoJudge) { Install-Tool 'overseer-judge' }
if (-not $NoLaunch) { Install-Tool 'overseer-launch' }

Write-Host '==> installed'
Show-Version 'multiplexer-driver'
if (-not $NoJudge) { Show-Version 'overseer-judge' }
if (-not $NoLaunch) { Show-Version 'overseer' }

Write-Host ''
Write-Host 'If an installer added %USERPROFILE%\.local\bin to your PATH, open a new'
Write-Host 'terminal before you use these.'
if (-not $NoLaunch) {
    Write-Host "Next: run 'overseer init' to write the example profile file."
}
