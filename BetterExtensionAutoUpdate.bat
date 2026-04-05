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
$AutoCleanupBackup = $true
$UseVersionedFolderName = $true
$KeepOnlyNewestInstallFolder = $true
$UpdateLogRelativePath = 'config\update_history.log'
$UpdateHashStateRelativePath = 'config\update_hash_state.json'

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

function Get-LocalVersionHintFromFolderName {
    param([string]$TargetDir)
    if ([string]::IsNullOrWhiteSpace($TargetDir)) { return $null }

    $leaf = Split-Path -Leaf $TargetDir
    if ([string]::IsNullOrWhiteSpace($leaf)) { return $null }

    if ($leaf -match '(?i)(\d+\.\d+\.\d+(?:\.\d+)?)') {
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

    $manifestVersionParsed = if ($versionRaw) { Get-SemVersion -Text $versionRaw } else { $null }

    $fileHintRaw = Get-LocalVersionHintFromFileName -TargetDir $TargetDir
    $fileHintParsed = if ($fileHintRaw) { Get-SemVersion -Text $fileHintRaw } else { $null }

    $folderHintRaw = Get-LocalVersionHintFromFolderName -TargetDir $TargetDir
    $folderHintParsed = if ($folderHintRaw) { Get-SemVersion -Text $folderHintRaw } else { $null }

    if (-not $manifestVersionParsed -and $fileHintParsed) {
        $versionRaw = $fileHintRaw
        $manifestVersionParsed = $fileHintParsed
    }

    if (-not $manifestVersionParsed -and $folderHintParsed) {
        $versionRaw = $folderHintRaw
        $manifestVersionParsed = $folderHintParsed
    }

    if ($manifestVersionParsed -and $folderHintParsed -and $folderHintParsed -gt $manifestVersionParsed) {
        $versionRaw = $folderHintRaw
        $manifestVersionParsed = $folderHintParsed
    }

    if (-not $versionRaw -and $fileHintRaw) {
        $versionRaw = $fileHintRaw
    } elseif (-not $versionRaw -and $folderHintRaw) {
        $versionRaw = $folderHintRaw
    }

    if (-not $dateDisplay -and (Test-Path -LiteralPath $TargetDir)) {
        $dirItem = Get-Item -LiteralPath $TargetDir -ErrorAction SilentlyContinue
        if ($dirItem) {
            $dateDisplay = $dirItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        }
    }

    if ($versionRaw) {
        $versionDisplay = Get-VersionDisplay -Text $versionRaw
        $versionParsed = if ($manifestVersionParsed) { $manifestVersionParsed } else { Get-SemVersion -Text $versionRaw }
    }

    return [pscustomobject]@{
        Exists         = (Test-Path -LiteralPath $TargetDir)
        VersionRaw     = $versionRaw
        VersionDisplay = $versionDisplay
        VersionParsed  = $versionParsed
        DateDisplay    = $dateDisplay
    }
}

function Get-VersionedFolderName {
    param(
        [string]$BaseName,
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $BaseName
    }

    $cleanVersion = ($VersionText.Trim() -replace '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($cleanVersion)) {
        return $BaseName
    }

    return ('{0}_{1}' -f $BaseName, $cleanVersion)
}

function Resolve-LocalProbeDir {
    param(
        [string]$ModsRoot,
        [string]$SelfHint,
        [string]$BatDir,
        [string]$ManifestName,
        [string]$DefaultFolderName
    )

    if ($SelfHint -and (Test-Path -LiteralPath $SelfHint)) {
        $resolvedSelf = (Resolve-Path -LiteralPath $SelfHint).Path.TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $resolvedSelf $ManifestName)) {
            return $resolvedSelf
        }
    }

    if ($BatDir -and (Test-Path -LiteralPath $BatDir)) {
        $resolvedBatDir = (Resolve-Path -LiteralPath $BatDir).Path.TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $resolvedBatDir $ManifestName)) {
            return $resolvedBatDir
        }
    }

    if ($ModsRoot -and (Test-Path -LiteralPath $ModsRoot)) {
        $exactDir = Join-Path $ModsRoot $DefaultFolderName
        if (Test-Path -LiteralPath (Join-Path $exactDir $ManifestName)) {
            return $exactDir
        }

        $candidates = @(Get-ChildItem -LiteralPath $ModsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ieq $DefaultFolderName -or
                $_.Name.StartsWith(($DefaultFolderName + '_'), [System.StringComparison]::OrdinalIgnoreCase)
            })

        $withManifest = @($candidates |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $ManifestName) } |
            Sort-Object LastWriteTime -Descending)
        if ($withManifest.Count -gt 0) {
            return $withManifest[0].FullName
        }

        if (Test-Path -LiteralPath $exactDir) {
            return $exactDir
        }

        if ($candidates.Count -gt 0) {
            return (@($candidates | Sort-Object LastWriteTime -Descending)[0]).FullName
        }
    }

    return $null
}

function Merge-ConfigFolderIntoTarget {
    param(
        [string]$SourceModDir,
        [string]$TargetModDir
    )

    $sourceConfigDir = Join-Path $SourceModDir 'config'
    if (-not (Test-Path -LiteralPath $sourceConfigDir)) {
        return $false
    }

    $targetConfigDir = Join-Path $TargetModDir 'config'
    New-Item -ItemType Directory -Path $targetConfigDir -Force | Out-Null
    Get-ChildItem -LiteralPath $sourceConfigDir -Force | Copy-Item -Destination $targetConfigDir -Recurse -Force
    return $true
}

function Write-UpdateLogEntry {
    param(
        [string]$ModDir,
        [string]$Result,
        [string]$FromVersion,
        [string]$ToVersion,
        [string]$TargetDir,
        [string]$LocalProbeDir,
        [string]$DownloadUrl,
        [string]$WorkRoot,
        [string]$ErrorMessage
    )

    if ([string]::IsNullOrWhiteSpace($ModDir)) {
        return $null
    }

    try {
        $logPath = Join-Path $ModDir $UpdateLogRelativePath
        $logDir = Split-Path -Parent $logPath
        if (-not [string]::IsNullOrWhiteSpace($logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        $safeFrom = if ([string]::IsNullOrWhiteSpace($FromVersion)) { '<unknown>' } else { $FromVersion }
        $safeTo = if ([string]::IsNullOrWhiteSpace($ToVersion)) { '<unknown>' } else { $ToVersion }
        $safeTarget = if ([string]::IsNullOrWhiteSpace($TargetDir)) { '<unknown>' } else { $TargetDir }
        $safeProbe = if ([string]::IsNullOrWhiteSpace($LocalProbeDir)) { '<unknown>' } else { $LocalProbeDir }
        $safeDownload = if ([string]::IsNullOrWhiteSpace($DownloadUrl)) { '<none>' } else { $DownloadUrl }
        $safeWork = if ([string]::IsNullOrWhiteSpace($WorkRoot)) { '<none>' } else { $WorkRoot }
        $safeError = if ([string]::IsNullOrWhiteSpace($ErrorMessage)) { '<none>' } else { $ErrorMessage }

        $entry = @(
            '============================================================',
            "[{0}] result={1}" -f $timestamp, $Result,
            "from={0}" -f $safeFrom,
            "to={0}" -f $safeTo,
            "target={0}" -f $safeTarget,
            "localProbe={0}" -f $safeProbe,
            "download={0}" -f $safeDownload,
            "workRoot={0}" -f $safeWork,
            "error={0}" -f $safeError
        )
        Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
        return $logPath
    } catch {
        return $null
    }
}

function Get-AssetSha256FromMetadata {
    param([object]$Asset)

    if (-not $Asset) {
        return $null
    }

    $candidates = @()
    if ($Asset.PSObject.Properties.Name -contains 'digest') {
        $candidates += [string]$Asset.digest
    }
    if ($Asset.PSObject.Properties.Name -contains 'label') {
        $candidates += [string]$Asset.label
    }
    if ($Asset.PSObject.Properties.Name -contains 'name') {
        $candidates += [string]$Asset.name
    }

    foreach ($raw in $candidates) {
        if ([string]::IsNullOrWhiteSpace($raw)) {
            continue
        }

        $text = $raw.Trim()
        if ($text -match '(?i)sha(?:256)?\s*[:=\-]\s*([a-f0-9]{64})') {
            return $matches[1].ToLowerInvariant()
        }
        if ($text -match '(?i)^([a-f0-9]{64})$') {
            return $matches[1].ToLowerInvariant()
        }
        if ($text -match '(?i)\b([a-f0-9]{64})\b') {
            return $matches[1].ToLowerInvariant()
        }
    }

    return $null
}

function Get-HashState {
    param([string]$ModDir)

    if ([string]::IsNullOrWhiteSpace($ModDir)) {
        return $null
    }

    $statePath = Join-Path $ModDir $UpdateHashStateRelativePath
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-HashState {
    param(
        [string]$ModDir,
        [string]$ReleaseTag,
        [string]$AssetName,
        [string]$AssetDigest,
        [string]$DownloadedZipSha256
    )

    if ([string]::IsNullOrWhiteSpace($ModDir)) {
        return $null
    }

    try {
        $statePath = Join-Path $ModDir $UpdateHashStateRelativePath
        $stateDir = Split-Path -Parent $statePath
        if (-not [string]::IsNullOrWhiteSpace($stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }

        $state = [ordered]@{
            updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            releaseTag = $ReleaseTag
            assetName = $AssetName
            assetDigestSha256 = $AssetDigest
            downloadedZipSha256 = $DownloadedZipSha256
        }

        $json = $state | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath $statePath -Value $json -Encoding UTF8
        return $statePath
    } catch {
        return $null
    }
}

function Schedule-DeferredDirectoryRemoval {
    param([string]$DirPath)

    if ([string]::IsNullOrWhiteSpace($DirPath)) {
        return $false
    }

    try {
        $cleanupArgs = '/c ping 127.0.0.1 -n 6 >nul & rmdir /s /q "' + $DirPath + '"'
        Start-Process -FilePath 'cmd.exe' -ArgumentList $cleanupArgs -WindowStyle Hidden
        return $true
    } catch {
        return $false
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
            AssetDigest    = Get-AssetSha256FromMetadata -Asset $asset
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

if (-not $modsRoot -or -not (Test-Path -LiteralPath $modsRoot)) {
    Write-Fail 'mods path is invalid and updater folder was not usable.'
    exit 2
}

$localProbeDir = Resolve-LocalProbeDir -ModsRoot $modsRoot -SelfHint $selfHint -BatDir $batDir -ManifestName $ManifestName -DefaultFolderName $DefaultFolderName
if (-not $localProbeDir) {
    $localProbeDir = Join-Path $modsRoot $DefaultFolderName
}

$local = Get-LocalMeta -TargetDir $localProbeDir -ManifestName $ManifestName
if ($local.VersionDisplay) {
    Write-Info ("Local version: {0}" -f $local.VersionDisplay)
} elseif ($local.DateDisplay) {
    Write-Info ("Local version: unknown (local time: {0})" -f $local.DateDisplay)
} else {
    Write-Info 'Local version: not installed'
}

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

$remoteAssetDigest = if ($selected.AssetDigest) { [string]$selected.AssetDigest } else { $null }
if ($remoteAssetDigest) {
    Write-Info ("Latest asset sha256: {0}" -f $remoteAssetDigest)
} else {
    Write-Warn 'Latest release asset did not expose a sha256 digest in metadata; download-time hash verification will be best-effort only.'
}

$fromText = if ($local.VersionDisplay) {
    $local.VersionDisplay
} elseif ($local.DateDisplay) {
    "unknown (local time: $($local.DateDisplay))"
} else {
    'not installed'
}
$toText = $remoteVersionText

$targetLeaf = if ($UseVersionedFolderName) {
    Get-VersionedFolderName -BaseName $DefaultFolderName -VersionText $toText
} else {
    $DefaultFolderName
}

$targetDir = Join-Path $modsRoot $targetLeaf
Write-Info ("Install target: {0} (versioned folder under mods root)" -f $targetDir)

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

$hashState = $null
if (-not $needUpdate) {
    $hashState = Get-HashState -ModDir $localProbeDir
    if ($remoteAssetDigest) {
        $localAssetDigest = if ($hashState -and $hashState.assetDigestSha256) {
            ([string]$hashState.assetDigestSha256).ToLowerInvariant()
        } else {
            $null
        }

        if ([string]::IsNullOrWhiteSpace($localAssetDigest)) {
            Write-Warn 'Version is equal but local hash state is missing; forcing revalidation update.'
            $needUpdate = $true
        } elseif ($localAssetDigest -ne $remoteAssetDigest.ToLowerInvariant()) {
            Write-Warn 'Version is equal but asset sha256 differs from local hash state; forcing revalidation update.'
            $needUpdate = $true
        }
    }
}

if (-not $needUpdate) {
    if (-not $hashState -and $remoteAssetDigest) {
        $backfillHashStatePath = Write-HashState -ModDir $localProbeDir -ReleaseTag $remoteTag -AssetName $ZipName -AssetDigest $remoteAssetDigest -DownloadedZipSha256 $null
        if ($backfillHashStatePath) {
            Write-Info ("Hash state backfilled: {0}" -f $backfillHashStatePath)
        } else {
            Write-Warn 'Failed to backfill hash state while up to date.'
        }
    }

    $legacyUpdateDir = Join-Path $modsRoot ($DefaultFolderName + '_Update')
    if (Test-Path -LiteralPath $legacyUpdateDir) {
        $resolvedLegacyUpdateDir = (Resolve-Path -LiteralPath $legacyUpdateDir).Path.TrimEnd('\')
        $resolvedBatDirForNoUpdate = $null
        if ($batDir -and (Test-Path -LiteralPath $batDir)) {
            $resolvedBatDirForNoUpdate = (Resolve-Path -LiteralPath $batDir).Path.TrimEnd('\')
        }

        if ($resolvedBatDirForNoUpdate -and $resolvedLegacyUpdateDir -ieq $resolvedBatDirForNoUpdate) {
            if (Schedule-DeferredDirectoryRemoval -DirPath $resolvedLegacyUpdateDir) {
                Write-Info ("Deferred cleanup scheduled: {0}" -f $resolvedLegacyUpdateDir)
            } else {
                Write-Warn ("Failed to schedule deferred cleanup: {0}" -f $resolvedLegacyUpdateDir)
            }
        } else {
            try {
                Remove-Item -LiteralPath $resolvedLegacyUpdateDir -Recurse -Force -ErrorAction Stop
                Write-Info ("Removed legacy updater folder: {0}" -f $resolvedLegacyUpdateDir)
            } catch {
                Write-Warn ("Could not remove legacy updater folder: {0}" -f $resolvedLegacyUpdateDir)
            }
        }
    }

    $noUpdateLogDir = if (Test-Path -LiteralPath $localProbeDir) { $localProbeDir } else { $targetDir }
    $noUpdateLogPath = Write-UpdateLogEntry -ModDir $noUpdateLogDir -Result 'UP_TO_DATE' -FromVersion $fromText -ToVersion $toText -TargetDir $targetDir -LocalProbeDir $localProbeDir -DownloadUrl $null -WorkRoot $null -ErrorMessage $null
    if ($noUpdateLogPath) {
        Write-Info ("Update log written: {0}" -f $noUpdateLogPath)
    }
    Write-Info ("Already up to date ({0})." -f $fromText)
    exit 0
}

Write-Info ("Update plan: {0} -> {1}" -f $fromText, $toText)

$workBase = $env:TEMP
$workRoot = Join-Path $workBase 'BetterExtension_Update'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

$tmpZip = Join-Path $workRoot ('BetterExtension_' + [guid]::NewGuid().ToString('N') + '.zip')
$tmpExpand = Join-Path $workRoot ('BetterExtension_expand_' + [guid]::NewGuid().ToString('N'))

$backupPath = $null
$deferredRemoveDir = $null
$downloadUrl = [string]$selected.Asset.browser_download_url
$downloadedZipHash = $null
try {
    Write-Info ("Download URL: {0}" -f $downloadUrl)
    Invoke-WebRequest -Uri $downloadUrl -Headers $Headers -OutFile $tmpZip -UseBasicParsing

    $downloadedZipHash = ((Get-FileHash -LiteralPath $tmpZip -Algorithm SHA256).Hash).ToLowerInvariant()
    Write-Info ("Downloaded zip sha256: {0}" -f $downloadedZipHash)
    if ($remoteAssetDigest -and ($downloadedZipHash -ne $remoteAssetDigest.ToLowerInvariant())) {
        throw ("Downloaded package hash mismatch. expected={0}, actual={1}" -f $remoteAssetDigest, $downloadedZipHash)
    }

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

    if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        try {
            if (Merge-ConfigFolderIntoTarget -SourceModDir $backupPath -TargetModDir $targetDir) {
                Write-Info ("Config migrated from backup: {0} -> {1}" -f (Join-Path $backupPath 'config'), (Join-Path $targetDir 'config'))
            }
        } catch {
            Write-Warn ("Failed to migrate config from backup: {0}" -f $backupPath)
        }

        if ($AutoCleanupBackup) {
            try {
                Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction Stop
                Write-Info ("Old backup removed: {0}" -f $backupPath)
            } catch {
                Write-Warn ("Could not remove old backup automatically: {0}" -f $backupPath)
            }
        } else {
            Write-Info ("Backup kept: {0}" -f $backupPath)
        }
    }

    if ($KeepOnlyNewestInstallFolder -and (Test-Path -LiteralPath $modsRoot)) {
        $resolvedTargetDir = (Resolve-Path -LiteralPath $targetDir).Path.TrimEnd('\')
        $resolvedBatDir = $null
        if ($batDir -and (Test-Path -LiteralPath $batDir)) {
            $resolvedBatDir = (Resolve-Path -LiteralPath $batDir).Path.TrimEnd('\')
        }

        $allInstallDirs = @(Get-ChildItem -LiteralPath $modsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -ieq $DefaultFolderName -or
                $_.Name.StartsWith(($DefaultFolderName + '_'), [System.StringComparison]::OrdinalIgnoreCase)
            } |
            Sort-Object LastWriteTime)

        foreach ($dir in $allInstallDirs) {
            $dirPath = $dir.FullName.TrimEnd('\')
            if ($dirPath -ieq $resolvedTargetDir) {
                continue
            }

            try {
                if (Merge-ConfigFolderIntoTarget -SourceModDir $dirPath -TargetModDir $targetDir) {
                    Write-Info ("Config migrated: {0} -> {1}" -f (Join-Path $dirPath 'config'), (Join-Path $targetDir 'config'))
                }
            } catch {
                Write-Warn ("Failed to migrate config from old folder: {0}" -f $dirPath)
            }

            if ($resolvedBatDir -and $dirPath -ieq $resolvedBatDir) {
                $deferredRemoveDir = $dirPath
                Write-Info ("Will remove updater helper folder after this script exits: {0}" -f $dirPath)
                continue
            }

            try {
                Remove-Item -LiteralPath $dirPath -Recurse -Force -ErrorAction Stop
                Write-Info ("Removed old install folder: {0}" -f $dirPath)
            } catch {
                Write-Warn ("Could not remove old install folder: {0}" -f $dirPath)
            }
        }
    }

    if ($deferredRemoveDir) {
        if (Schedule-DeferredDirectoryRemoval -DirPath $deferredRemoveDir) {
            Write-Info ("Deferred cleanup scheduled: {0}" -f $deferredRemoveDir)
        } else {
            Write-Warn ("Failed to schedule deferred cleanup: {0}" -f $deferredRemoveDir)
        }
    }

    $successLogPath = Write-UpdateLogEntry -ModDir $targetDir -Result 'SUCCESS' -FromVersion $fromText -ToVersion $toText -TargetDir $targetDir -LocalProbeDir $localProbeDir -DownloadUrl $downloadUrl -WorkRoot $workRoot -ErrorMessage $null
    if ($successLogPath) {
        Write-Info ("Update log written: {0}" -f $successLogPath)
    }

    $hashStatePath = Write-HashState -ModDir $targetDir -ReleaseTag $remoteTag -AssetName $ZipName -AssetDigest $remoteAssetDigest -DownloadedZipSha256 $downloadedZipHash
    if ($hashStatePath) {
        Write-Info ("Hash state written: {0}" -f $hashStatePath)
    } else {
        Write-Warn 'Failed to write hash state file.'
    }

    Write-Info ("Update done: {0} -> {1}" -f $fromText, $toText)
    Write-Info ("Updated folder: {0}" -f $targetDir)
    $scalingConfigPath = Join-Path $targetDir 'config\multiplayer_scaling.jsonc'
    $scalingGuidePath = Join-Path $targetDir 'config\MULTIPLAYER_SCALING_BEGINNER_GUIDE.zh-CN.md'
    if (Test-Path -LiteralPath $scalingConfigPath) {
        Write-Info ("Multiplayer scaling config: {0}" -f $scalingConfigPath)
    }
    if (Test-Path -LiteralPath $scalingGuidePath) {
        Write-Info ("Multiplayer scaling guide (beginner): {0}" -f $scalingGuidePath)
        Write-Info "Tip: open the guide first, then fill multiplayer_scaling.jsonc step by step."
    }
    Write-Info ("Work files kept at: {0}" -f $workRoot)
    exit 0
} catch {
    $errorMessage = $_.Exception.Message
    Write-Fail ("Update failed: {0}" -f $errorMessage)

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

    $failedLogDir = if (Test-Path -LiteralPath $targetDir) {
        $targetDir
    } elseif ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        $backupPath
    } else {
        $localProbeDir
    }
    $failedLogPath = Write-UpdateLogEntry -ModDir $failedLogDir -Result 'FAILED' -FromVersion $fromText -ToVersion $toText -TargetDir $targetDir -LocalProbeDir $localProbeDir -DownloadUrl $downloadUrl -WorkRoot $workRoot -ErrorMessage $errorMessage
    if ($failedLogPath) {
        Write-Warn ("Update log written: {0}" -f $failedLogPath)
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
  for %%I in ("%BE_BAT_DIR%") do set "BE_BAT_LEAF=%%~nxI"
  if /I not "!BE_BAT_LEAF!"=="mods" (
    echo %BE_BAT_DIR% | findstr /I /C:"\mods\" >nul
    if not errorlevel 1 (
      set "BE_SELF_MOD_DIR=%BE_BAT_DIR%"
    )
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
  pause
)

exit /b %PS_EXIT%
