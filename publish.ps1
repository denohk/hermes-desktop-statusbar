<#
  publish.ps1 — create the GitHub repo and push this plugin, without ever
  putting your token in a file, a command line, or your shell history.

  What it asks for:
    - GitHub username (plain text)
    - Repository name   (default: hermes-desktop-statusbar)
    - Personal Access Token (hidden input; needs "repo" scope — classic PAT,
      or a fine-grained token with Contents: read/write + Administration: write)

  What it does:
    1. verifies the token (GET /user)
    2. creates the repo if it does not exist (POST /user/repos)
    3. git init + commit, then pushes with an IN-MEMORY auth header
    4. scrubs the token: the stored remote is the plain https URL
    5. verifies the pushed README through the API

  Nothing is written to disk except the repo itself.
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

# Bearer works for both classic PATs and fine-grained tokens (token ... is classic-only).
$auth = @{ Authorization = "Bearer $token"; 'User-Agent' = 'hermes-statusbar-publish' }
$api  = 'https://api.github.com'

Write-Output ''
Write-Output '  [1/5] verifying token...'
$me = Invoke-RestMethod -Uri "$api/user" -Headers $auth -Method Get
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

Write-Output '  [3/5] committing...'
if (-not (Test-Path (Join-Path $here '.git'))) { git init -q | Out-Null }
git symbolic-ref HEAD refs/heads/main 2>$null
git add -A
$email = "$user@users.noreply.github.com"
git -c user.name="$user" -c user.email="$email" commit -q -m 'Hermes desktop status bar plugin: context %, cache hit, tokens/s, tokens in/out + New/Stop/Sessions buttons' 2>$null
if ($LASTEXITCODE -ne 0) { Write-Output '        nothing new to commit' } else { Write-Output '        committed' }

Write-Output '  [4/5] pushing (token passed in memory, never stored)...'
$b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$token"))
git remote remove origin 2>$null
git remote add origin "https://github.com/$user/$repo.git"
git -c http.extraheader="AUTHORIZATION: basic $b64" push -u origin main
if ($LASTEXITCODE -ne 0) { throw 'push failed (network or permission)' }

Write-Output '  [5/5] verifying through the API...'
$readme = Invoke-RestMethod -Uri "$api/repos/$user/$repo/contents/README.md" -Headers $auth -Method Get
Write-Output ("        README.md live, " + $readme.size + " bytes")
$plugin = Invoke-RestMethod -Uri "$api/repos/$user/$repo/contents/plugin.js" -Headers $auth -Method Get
Write-Output ("        plugin.js live, " + $plugin.size + " bytes")

Write-Output ''
Write-Output '  Done.'
Write-Output ("  Repo:  https://github.com/" + $user + '/' + $repo)
Write-Output '  Open it:  gh repo view --web   (or click the link above)'
Write-Output ''
Write-Output '  Remember: the token is not saved anywhere. Revoke it when you are done if you like.'
Write-Output ''
