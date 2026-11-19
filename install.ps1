<#
  install.ps1 — install the Hermes desktop status bar plugin.

  Copies plugin.js into <HERMES_HOME>\desktop-plugins\hermes-desktop-statusbar\plugin.js
  HERMES_HOME resolves to the env var if set, else %LOCALAPPDATA%\hermes (Windows)
  or ~/.hermes (macOS/Linux).

  Usage:  powershell -ExecutionPolicy Bypass -File install.ps1
#>
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here 'plugin.js'
if (-not (Test-Path $src)) { throw "plugin.js not found next to this script ($here)" }

if ($env:HERMES_HOME) {
  $home_ = $env:HERMES_HOME
} elseif ($env:LOCALAPPDATA) {
  $home_ = Join-Path $env:LOCALAPPDATA 'hermes'
} else {
  $home_ = Join-Path $HOME '.hermes'
}

$destDir = Join-Path $home_ 'desktop-plugins\hermes-desktop-statusbar'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

# Back up an existing copy instead of clobbering it silently.
$dest = Join-Path $destDir 'plugin.js'
if (Test-Path $dest) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  Copy-Item $dest (Join-Path $destDir "plugin.js.bak-$stamp")
}

Copy-Item $src $dest -Force

Write-Output ''
Write-Output '  Installed:'
Write-Output "    $dest"
Write-Output ''
Write-Output '  Next: in the Hermes desktop app press Ctrl/Cmd+K'
Write-Output '        -> "Reload desktop plugins"'
Write-Output '        The chip appears at the right end of the status bar.'
Write-Output ''
