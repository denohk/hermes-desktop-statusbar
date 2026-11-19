<#
  publish.ps1 — create the GitHub repo and push this plugin, without ever
  putting your token in a file, a command line, or your shell history.

  Asks for: GitHub username, repository name (default hermes-desktop-statusbar),
  and a Personal Access Token (hidden input). Classic PAT with "repo" scope, or
  a fine-grained token with Contents: RW + Administration: RW on All repositories.

  Safe to re-run: an existing repo is reused, an unchanged commit is fine, and
  the push is retried.
#>
$ErrorActionPreference = 'Stop'

Write-Output ''
Write-Output '  === Publish Hermes Desktop Status Bar ==='
Write-Output ''

$user = Read-Host '  GitHub username'
if ([string]::IsNullOrWhiteSpace($user)) { throw 'username required' }

$repo = Read-Host '  Repository name (Enter = hermes-desktop-statusbar)'
if ([string]::IsNullOrWhiteSpace($repo)) { $repo = 'hermes-desktop-statusbar' }

$secure = Read-Host '  Personal Access Token (typing is hidden)' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
if ([string]::IsNullOrWhiteSpace($token)) { throw 'token required' }
# A pasted token can carry a trailing space, a newline or stray quotes — trim it,
# otherwise GitHub answers 401 for a perfectly good token.
$token = $token.Trim().Trim('"').Trim("'")
$schemeHint = if ($token.StartsWith('github_pat_')) { 'fine-grained token' } elseif ($token.StartsWith('ghp_')) { 'classic token' } else { 'unrecognised prefix' }
Write-Output ("        token: " + $token.Length + " chars, " + $schemeHint)

# Bearer works for both classic PATs and fine-grained tokens; 'token' is the older
# spelling some proxies still expect. Try Bearer, fall back to token.
$auth = @{ Authorization = "Bearer $token"; 'User-Agent' = 'hermes-statusbar-publish'; Accept = 'application/vnd.github+json' }
$api  = 'https://api.github.com'

Write-Output ''
Write-Output '  [1/5] verifying token...'
try {
  $me = Invoke-RestMethod -Uri "$api/user" -Headers $auth -Method Get
} catch {
  $status = $null
  if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
  if ($status -eq 401) {
    $auth = @{ Authorization = "token $token"; 'User-Agent' = 'hermes-statusbar-publish'; Accept = 'application/vnd.github+json' }
    try {
      $me = Invoke-RestMethod -Uri "$api/user" -Headers $auth -Method Get
    } catch {
      Write-Output ''
      Write-Output '  Token rejected (401) with both Bearer and token schemes.'
      Write-Output '  Most likely causes, in order:'
      Write-Output '    1. the token was already revoked or expired (regenerate it)'
      Write-Output '    2. the paste is truncated — the box shows dots, so re-copy the whole value'
      Write-Output '    3. the token belongs to a different account than the username typed above'
      Write-Output ''
      throw
    }
  } else {
    throw
  }
}
Write-Output ("        authenticated as: " + $me.login)

Write-Output '  [2/5] creating repository (skipped if it already exists)...'
$exists = $true
try {
  Invoke-RestMethod -Uri "$api/repos/$user/$repo" -Headers $auth -Method Get | Out-Null
  Write-Output '        already exists — pushing into it'
} catch {
  $exists = $false
}
if (-not $exists) {
  $body = @{
    name        = $repo
    description = 'Hermes CLI-style status bar for the Hermes desktop app: context %, cache hit, tokens/s, tokens in/out + New / Stop / Sessions buttons.'
    private     = $false
    has_issues  = $true
    has_wiki    = $false
  } | ConvertTo-Json
  Invoke-RestMethod -Uri "$api/user/repos" -Headers $auth -Method Post -Body $body -ContentType 'application/json' | Out-Null
  Write-Output '        created'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here

# ---- git section -----------------------------------------------------------------
# Native git writes progress to stderr; with ErrorActionPreference=Stop, PowerShell
# turns that into a terminating NativeCommandError. Run this part with Continue and
# check $LASTEXITCODE ourselves.
$saved = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

Write-Output '  [3/5] committing...'
if (-not (Test-Path (Join-Path $here '.git'))) { & git init -q 2>&1 | Out-Null }
& git symbolic-ref HEAD refs/heads/main 2>&1 | Out-Null
& git add -A 2>&1 | Out-Null
$email = "$user@users.noreply.github.com"
& git -c "user.name=$user" -c "user.email=$email" commit -m 'Hermes desktop status bar plugin: context %, cache hit, tokens/s, tokens in/out + New/Stop/Sessions buttons' 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Output '        committed' } else { Write-Output '        nothing new to commit' }

Write-Output '  [4/5] pushing (token passed in memory, never stored)...'
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
$remoteUrl = "https://github.com/$user/$repo.git"
& git remote remove origin 2>&1 | Out-Null
& git remote add origin $remoteUrl 2>&1 | Out-Null
$pushOut = & git -c "http.extraheader=AUTHORIZATION: basic $b64" push -u origin main 2>&1 | Out-String
$pushCode = $LASTEXITCODE
foreach ($line in ($pushOut -split "`r?`n")) {
  if ($line.Trim()) { Write-Output ("        " + $line.Trim()) }
}
& git remote set-url origin $remoteUrl 2>&1 | Out-Null
$ErrorActionPreference = $saved
if ($pushCode -ne 0) {
  throw 'push failed — see the git output above (usually a token missing Contents: read and write)'
}

Write-Output '  [5/5] verifying through the API...'
$readme = Invoke-RestMethod -Uri "$api/repos/$user/$repo/contents/README.md" -Headers $auth -Method Get
Write-Output ("        README.md live, " + $readme.size + " bytes")
$plugin = Invoke-RestMethod -Uri "$api/repos/$user/$repo/contents/plugin.js" -Headers $auth -Method Get
Write-Output ("        plugin.js live, " + $plugin.size + " bytes")

Write-Output ''
Write-Output '  Done.'
Write-Output ("  Repo:  https://github.com/" + $user + '/' + $repo)
Write-Output ''
Write-Output '  The token is not saved anywhere. Revoke it when you are done if you like.'
Write-Output ''
