@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>nul
goto :MAIN

:::BEGIN_PS1
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [Console]::OutputEncoding

$Repo = 'PnLament/BetterExtensionMod'
$ZipName = 'BetterExtension.zip'
$ManifestName = 'BetterExtension.json'
$DefaultFolderName = 'BetterExtension'
$Api = "https://api.github.com/repos/$Repo/releases"
$Headers = @{
    'User-Agent' = 'BetterExtension-Updater/2.0'
    'Accept'     = 'application/vnd.github+json'
}

function Write-Info {
    param([string]$Message)
    Write-Host ("[INFO] {0}" -f $Message)
}

function Write-Warn {
    param([string]$Message)
    Write-Host ("[WARN] {0}" -f $Message) -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host ("[ERROR] {0}" -f $Message) -ForegroundColor Red
}

function Get-SemVersion {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '(?i)v?\s*(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $build = [int]$matches[3]
        if ($matches[4]) {
            return [version]::new($major, $minor, $build, [int]$matches[4])
        }
        return [version]::new($major, $minor, $build)
    }
    return $null
}

function Get-VersionDisplay {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $v = Get-SemVersion -Text $Text
    if ($v) { return $v.ToString() }
    return $Text.Trim()
}

function Normalize-VersionToken {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    return (($Text -replace '(?i)^\s*v', '').Trim())
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $encodings = @(
        (New-Object System.Text.UTF8Encoding($false, $true)),
        (New-Object System.Text.UTF8Encoding($true, $true)),
        [System.Text.Encoding]::GetEncoding(936),
        [System.Text.Encoding]::Unicode,
        [System.Text.Encoding]::BigEndianUnicode
    )

    foreach ($enc in $encodings) {
        try {
            $raw = [System.IO.File]::ReadAllText($Path, $enc)
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            return $raw | ConvertFrom-Json
        } catch {
        }
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw) | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-LocalVersionHintFromFileName {
    param([string]$TargetDir)
    if (-not (Test-Path -LiteralPath $TargetDir)) { return $null }

    $candidate = Get-ChildItem -LiteralPath $TargetDir -File -Filter '*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)v\d+\.\d+\.\d+' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $candidate) { return $null }
    if ($candidate.Name -match '(?i)(v?\d+\.\d+\.\d+(?:\.\d+)?)') {
        return $matches[1]
    }
    return $null
}

function Get-LocalMeta {
    param(
        [string]$TargetDir,
        [string]$ManifestName
    )

    $manifestPath = Join-Path $TargetDir $ManifestName
    $versionRaw = $null
    $versionDisplay = $null
    $versionParsed = $null
    $dateDisplay = $null

    if (Test-Path -LiteralPath $manifestPath) {
        $json = Read-JsonFile -Path $manifestPath
        if ($json -and $json.version) {
            $versionRaw = [string]$json.version
        }
        $manifestItem = Get-Item -LiteralPath $manifestPath -ErrorAction SilentlyContinue
        if ($manifestItem) {
            $dateDisplay = $manifestItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    if (-not $versionRaw) {
        $versionRaw = Get-LocalVersionHintFromFileName -TargetDir $TargetDir
    }

    if (-not $dateDisplay -and (Test-Path -LiteralPath $TargetDir)) {
        $dirItem = Get-Item -LiteralPath $TargetDir -ErrorAction SilentlyContinue
        if ($dirItem) {
            $dateDisplay = $dirItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    if ($versionRaw) {
        $versionDisplay = Get-VersionDisplay -Text $versionRaw
        $versionParsed = Get-SemVersion -Text $versionRaw
    }

    return [pscustomobject]@{
        Exists         = (Test-Path -LiteralPath $TargetDir)
        VersionRaw     = $versionRaw
        VersionDisplay = $versionDisplay
        VersionParsed  = $versionParsed
        DateDisplay    = $dateDisplay
    }
}

function Get-ReleaseCandidates {
    param(
        [object[]]$Releases,
        [string]$ZipName
    )

    $result = @()
    foreach ($rel in @($Releases)) {
        if (-not $rel -or $rel.draft) { continue }

        $asset = @($rel.assets | Where-Object { $_.name -ieq $ZipName }) | Select-Object -First 1
        if (-not $asset -or -not $asset.browser_download_url) { continue }

        $tag = [string]$rel.tag_name
        $parsed = Get-SemVersion -Text $tag
        $publishedAt = [datetime]::MinValue
        if ($rel.published_at) {
            [void][datetime]::TryParse([string]$rel.published_at, [ref]$publishedAt)
        }

        $result += [pscustomobject]@{
            Release        = $rel
            Asset          = $asset
            Tag            = $tag
            ParsedVersion  = $parsed
            DisplayVersion = if ($parsed) { $parsed.ToString() } elseif ($tag) { $tag } else { 'unknown' }
            IsPrerelease   = [bool]$rel.prerelease
            PublishedAt    = $publishedAt
        }
    }

    return $result
}

function Select-LatestRelease {
    param([object[]]$Candidates)

    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

    $stableVersioned = @($Candidates |
        Where-Object { -not $_.IsPrerelease -and $_.ParsedVersion } |
        Sort-Object ParsedVersion, PublishedAt -Descending)
    if ($stableVersioned.Count -gt 0) { return $stableVersioned[0] }

    $anyVersioned = @($Candidates |
        Where-Object { $_.ParsedVersion } |
        Sort-Object ParsedVersion, PublishedAt -Descending)
    if ($anyVersioned.Count -gt 0) { return $anyVersioned[0] }

    $stable = @($Candidates |
        Where-Object { -not $_.IsPrerelease } |
        Sort-Object PublishedAt -Descending)
    if ($stable.Count -gt 0) { return $stable[0] }

    return @($Candidates | Sort-Object PublishedAt -Descending)[0]
}

$modsRoot = $env:BE_MODS
$selfHint = $env:BE_SELF_MOD_DIR
$batDir = $env:BE_BAT_DIR

if ($modsRoot -and (Test-Path -LiteralPath $modsRoot)) {
    $modsRoot = (Resolve-Path -LiteralPath $modsRoot).Path
}

$targetDir = $null
$targetReason = $null

if ($selfHint -and (Test-Path -LiteralPath $selfHint)) {
    $resolvedSelf = (Resolve-Path -LiteralPath $selfHint).Path.TrimEnd('\')
    if ((Split-Path -Leaf $resolvedSelf) -ine 'mods') {
        $targetDir = $resolvedSelf
        $targetReason = 'use updater folder as target'
    }
}

if (-not $targetDir -and $batDir -and (Test-Path -LiteralPath $batDir)) {
    $resolvedBatDir = (Resolve-Path -LiteralPath $batDir).Path.TrimEnd('\')
    if (Test-Path -LiteralPath (Join-Path $resolvedBatDir $ManifestName)) {
        $targetDir = $resolvedBatDir
        $targetReason = 'manifest found beside updater'
    }
}

if (-not $targetDir) {
    if (-not $modsRoot -or -not (Test-Path -LiteralPath $modsRoot)) {
        Write-Fail 'mods path is invalid and updater folder was not usable.'
        exit 2
    }
    $targetDir = Join-Path $modsRoot $DefaultFolderName
    $targetReason = 'fallback to mods\\BetterExtension'
}

$local = Get-LocalMeta -TargetDir $targetDir -ManifestName $ManifestName
if ($local.VersionDisplay) {
    Write-Info ("Local version: {0}" -f $local.VersionDisplay)
} elseif ($local.DateDisplay) {
    Write-Info ("Local version: unknown (local time: {0})" -f $local.DateDisplay)
} else {
    Write-Info 'Local version: not installed'
}
Write-Info ("Install target: {0} ({1})" -f $targetDir, $targetReason)

try {
    $releasesRaw = Invoke-RestMethod -Uri $Api -Headers $Headers -Method Get
} catch {
    Write-Fail ("Could not query GitHub releases: {0}" -f $_.Exception.Message)
    exit 3
}

$candidates = @(Get-ReleaseCandidates -Releases @($releasesRaw) -ZipName $ZipName)
if ($candidates.Count -lt 1) {
    Write-Fail ("No release with asset '{0}' was found." -f $ZipName)
    exit 4
}

$selected = Select-LatestRelease -Candidates $candidates
if (-not $selected) {
    Write-Fail 'Failed to select latest release.'
    exit 5
}

$remoteVersionText = $selected.DisplayVersion
$remoteTag = $selected.Tag
Write-Info ("Latest release: {0} ({1})" -f $remoteVersionText, $remoteTag)

$fromText = if ($local.VersionDisplay) {
    $local.VersionDisplay
} elseif ($local.DateDisplay) {
    "unknown (local time: $($local.DateDisplay))"
} else {
    'not installed'
}
$toText = $remoteVersionText

$needUpdate = $true
if ($local.VersionParsed -and $selected.ParsedVersion) {
    if ($selected.ParsedVersion -le $local.VersionParsed) {
        $needUpdate = $false
    }
} elseif ($local.VersionRaw) {
    if ((Normalize-VersionToken -Text $local.VersionRaw) -eq (Normalize-VersionToken -Text $remoteTag)) {
        $needUpdate = $false
    }
}

if (-not $needUpdate) {
    Write-Info ("Already up to date ({0})." -f $fromText)
    exit 0
}

Write-Info ("Update plan: {0} -> {1}" -f $fromText, $toText)

$workBase = if ($batDir -and (Test-Path -LiteralPath $batDir)) { $batDir } else { $env:TEMP }
$workRoot = Join-Path $workBase 'BetterExtension_Update'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

$tmpZip = Join-Path $workRoot ('BetterExtension_' + [guid]::NewGuid().ToString('N') + '.zip')
$tmpExpand = Join-Path $workRoot ('BetterExtension_expand_' + [guid]::NewGuid().ToString('N'))

$backupPath = $null
try {
    Write-Info ("Download URL: {0}" -f $selected.Asset.browser_download_url)
    Invoke-WebRequest -Uri $selected.Asset.browser_download_url -Headers $Headers -OutFile $tmpZip -UseBasicParsing

    New-Item -ItemType Directory -Path $tmpExpand -Force | Out-Null
    Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpExpand -Force

    $jsonHits = @(Get-ChildItem -LiteralPath $tmpExpand -Recurse -File -Filter $ManifestName -ErrorAction SilentlyContinue)
    $sourceDir = $null
    if ($jsonHits.Count -gt 0) {
        $targetLeaf = Split-Path -Leaf $targetDir
        $leafHit = @($jsonHits | Where-Object { $_.Directory.Name -ieq $targetLeaf }) | Select-Object -First 1
        if ($leafHit) {
            $sourceDir = $leafHit.Directory.FullName
        } else {
            $defaultHit = @($jsonHits | Where-Object { $_.Directory.Name -ieq $DefaultFolderName }) | Select-Object -First 1
            if ($defaultHit) {
                $sourceDir = $defaultHit.Directory.FullName
            } else {
                $sourceDir = $jsonHits[0].Directory.FullName
            }
        }
    }

    if (-not $sourceDir) {
        if (Test-Path -LiteralPath (Join-Path $tmpExpand $ManifestName)) {
            $sourceDir = $tmpExpand
        } else {
            throw ("Package does not contain '{0}'." -f $ManifestName)
        }
    }

    $parentDir = Split-Path -Parent $targetDir
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $targetDir) {
        $backupName = (Split-Path -Leaf $targetDir) + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
        $backupPath = Join-Path $parentDir $backupName
        Rename-Item -LiteralPath $targetDir -NewName $backupName
        Write-Info ("Backup created: {0}" -f $backupPath)
    }

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceDir -Force | Copy-Item -Destination $targetDir -Recurse -Force

    Write-Info ("Update done: {0} -> {1}" -f $fromText, $toText)
    Write-Info ("Updated folder: {0}" -f $targetDir)
    Write-Info ("Work files kept at: {0}" -f $workRoot)
    exit 0
} catch {
    Write-Fail ("Update failed: {0}" -f $_.Exception.Message)

    if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        try {
            if (Test-Path -LiteralPath $targetDir) {
                $failedName = (Split-Path -Leaf $targetDir) + '.failed_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
                Rename-Item -LiteralPath $targetDir -NewName $failedName -ErrorAction SilentlyContinue
            }
            Rename-Item -LiteralPath $backupPath -NewName (Split-Path -Leaf $targetDir) -ErrorAction Stop
            Write-Warn 'Rollback completed from backup.'
        } catch {
            Write-Warn ("Rollback failed, backup remains at: {0}" -f $backupPath)
        }
    }

    exit 20
}
:::END_PS1

:MAIN
set "BE_BAT=%~f0"
for %%I in ("%~dp0.") do set "BE_BAT_DIR=%%~fI"

set "BE_MANIFEST=BetterExtension.json"
set "BE_MODS="
set "BE_SELF_MOD_DIR="

REM Prefer updater folder when it is clearly a mod folder.
if exist "%BE_BAT_DIR%\%BE_MANIFEST%" (
  set "BE_SELF_MOD_DIR=%BE_BAT_DIR%"
)

if not defined BE_SELF_MOD_DIR (
  echo %BE_BAT_DIR% | findstr /I /C:"\mods\" >nul
  if not errorlevel 1 (
    set "BE_SELF_MOD_DIR=%BE_BAT_DIR%"
  )
)

if defined BE_SELF_MOD_DIR (
  for %%I in ("%BE_SELF_MOD_DIR%\..") do set "BE_MODS=%%~fI"
)

REM Common Steam paths.
if not defined BE_MODS if exist "%ProgramFiles(x86)%\Steam\steamapps\common\Slay the Spire 2\mods\" (
  set "BE_MODS=%ProgramFiles(x86)%\Steam\steamapps\common\Slay the Spire 2\mods"
)
if not defined BE_MODS if exist "%ProgramFiles%\Steam\steamapps\common\Slay the Spire 2\mods\" (
  set "BE_MODS=%ProgramFiles%\Steam\steamapps\common\Slay the Spire 2\mods"
)

REM Read Steam install path from registry.
if not defined BE_MODS (
  for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul ^| findstr /i InstallPath') do (
    set "STEAMROOT=%%B"
  )
  if defined STEAMROOT if exist "!STEAMROOT!\steamapps\common\Slay the Spire 2\mods\" (
    set "BE_MODS=!STEAMROOT!\steamapps\common\Slay the Spire 2\mods"
  )
)

REM Extra common library path.
if not defined BE_MODS if exist "D:\SteamLibrary\steamapps\common\Slay the Spire 2\mods\" (
  set "BE_MODS=D:\SteamLibrary\steamapps\common\Slay the Spire 2\mods"
)

REM mods under script or working directory.
if not defined BE_MODS if exist "%~dp0mods\" (
  set "BE_MODS=%~dp0mods"
)
if not defined BE_MODS if exist "%CD%\mods\" (
  set "BE_MODS=%CD%\mods"
)

if not defined BE_MODS (
  echo [ERROR] Could not find Slay the Spire 2 mods folder.
  echo Put this updater under a mod folder, or run it on a machine with Steam install path available.
  pause
  exit /b 1
)

echo [INFO] Mods root: !BE_MODS!
if defined BE_SELF_MOD_DIR (
  echo [INFO] Target folder priority: !BE_SELF_MOD_DIR!
) else (
  echo [INFO] Target folder fallback: !BE_MODS!\BetterExtension
)

set "BE_BAT=%~f0"
set "BE_BAT_DIR=%BE_BAT_DIR%"
set "BE_MODS=!BE_MODS!"
set "BE_SELF_MOD_DIR=!BE_SELF_MOD_DIR!"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$enc = New-Object System.Text.UTF8Encoding($false); $raw = [System.IO.File]::ReadAllText($env:BE_BAT, $enc); $s = ':::BEGIN_PS1'; $e = ':::END_PS1'; $i = $raw.IndexOf($s); $j = $raw.IndexOf($e); if ($i -lt 0 -or $j -lt 0) { Write-Host '[ERROR] Embedded script markers are missing.' -ForegroundColor Red; exit 99 }; $code = $raw.Substring($i + $s.Length, $j - $i - $s.Length).Trim(); $fn = [System.IO.Path]::Combine($env:TEMP, ('beu_' + [guid]::NewGuid().ToString('N') + '.ps1')); [System.IO.File]::WriteAllText($fn, $code, (New-Object System.Text.UTF8Encoding($true))); & $fn; $c = $LASTEXITCODE; Remove-Item -LiteralPath $fn -Force -ErrorAction SilentlyContinue; exit $c"

set "PS_EXIT=%ERRORLEVEL%"
if not "%PS_EXIT%"=="0" (
  echo.
  echo [TIP] If GitHub is unreachable, check your network or proxy settings.
  echo Releases page: https://github.com/PnLament/BetterExtensionMod/releases
)

pause
exit /b %PS_EXIT%
