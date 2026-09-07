$ErrorActionPreference = "Stop"

# ============================================================
# TDC Valheim Installer / Updater
# Bootstrap v0.3.0
# ============================================================

$RepoOwner = "willg-dev"
$RepoName  = "valheim_tdc"
$Branch    = "main"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

$ManifestUrl = "$RawBase/manifest.json"
$LocalManifestName = "TDCValheimPack.manifest.json"
$VersionFileName   = "TDCValheimPack.version"
$BackupFolderName  = "TDCModpackBackups"

function Write-Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host "                 TDC VALHEIM INSTALLER"
    Write-Host "============================================================"
    Write-Host ""
}

function Get-ValheimPath {
    $candidates = @()

    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\Valheim")
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Steam\steamapps\common\Valheim")
    }

    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath -ErrorAction Stop).SteamPath
        if ($steamPath) {
            $candidates += (Join-Path $steamPath "steamapps\common\Valheim")

            # Parse additional Steam libraries from libraryfolders.vdf.
            $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $matches = Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches
                foreach ($m in $matches.Matches) {
                    $lib = $m.Groups[1].Value -replace '\\\\','\'
                    $candidates += (Join-Path $lib "steamapps\common\Valheim")
                }
            }
        }
    } catch {}

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path (Join-Path $candidate "valheim.exe")) {
            return $candidate
        }
    }

    Write-Host "Valheim was not found automatically." -ForegroundColor Yellow
    Write-Host "In Steam: Library > Valheim > Manage > Browse local files"
    Write-Host ""
    $manual = Read-Host "Paste the Valheim folder path"
    $manual = $manual.Trim('"')

    if (-not (Test-Path (Join-Path $manual "valheim.exe"))) {
        throw "valheim.exe was not found at '$manual'."
    }
    return $manual
}

function Get-RemoteManifest {
    Write-Host "Checking TDC repository..."
    try {
        return Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
    } catch {
        throw "Could not download manifest.json from GitHub. $($_.Exception.Message)"
    }
}

function Get-InstalledManifest($ValheimPath) {
    $path = Join-Path $ValheimPath $LocalManifestName
    if (Test-Path $path) {
        try { return Get-Content $path -Raw | ConvertFrom-Json }
        catch { Write-Host "[WARN] Existing TDC manifest is unreadable." -ForegroundColor Yellow }
    }
    return $null
}

function Backup-TDC($ValheimPath) {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backup = Join-Path $ValheimPath "$BackupFolderName\$stamp"
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $targets = @("BepInEx", "winhttp.dll", "doorstop_config.ini",
                 $VersionFileName, $LocalManifestName)

    foreach ($target in $targets) {
        $src = Join-Path $ValheimPath $target
        if (Test-Path $src) {
            Copy-Item $src $backup -Recurse -Force
        }
    }
    return $backup
}

function Remove-OldManagedFiles($ValheimPath, $OldManifest) {
    if (-not $OldManifest -or -not $OldManifest.files) { return }

    Write-Host "Removing files owned by the previous TDC pack..."
    foreach ($file in $OldManifest.files) {
        if (-not $file.destination) { continue }
        $dest = Join-Path $ValheimPath $file.destination

        # Safety: only files explicitly recorded in the installed TDC manifest.
        if (Test-Path $dest -PathType Leaf) {
            Remove-Item $dest -Force
        }
    }
}

function Get-FileSha256($Path) {
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Install-File($ValheimPath, $File) {
    if (-not $File.name -or -not $File.url -or -not $File.destination -or -not $File.sha256) {
        throw "Manifest contains an incomplete file entry."
    }

    $expected = $File.sha256.ToLowerInvariant()
    if ($expected -notmatch '^[a-f0-9]{64}$') {
        throw "Invalid SHA-256 for $($File.name)."
    }

    $temp = Join-Path $env:TEMP ("tdc_" + [Guid]::NewGuid().ToString("N"))
    try {
        Write-Host ("Downloading {0}..." -f $File.name)
        Invoke-WebRequest -Uri $File.url -OutFile $temp -UseBasicParsing

        $actual = Get-FileSha256 $temp
        if ($actual -ne $expected) {
            throw "SHA-256 mismatch for $($File.name). Expected $expected but received $actual."
        }

        $dest = Join-Path $ValheimPath $File.destination
        $parent = Split-Path $dest -Parent
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        Copy-Item $temp $dest -Force
        Write-Host ("[OK] {0}" -f $File.name) -ForegroundColor Green
    }
    finally {
        if (Test-Path $temp) { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Verify-Pack($ValheimPath, $Manifest) {
    $bad = @()
    foreach ($file in $Manifest.files) {
        $dest = Join-Path $ValheimPath $file.destination
        if (-not (Test-Path $dest -PathType Leaf)) {
            $bad += "$($file.name) - missing"
            continue
        }

        $actual = Get-FileSha256 $dest
        if ($actual -ne $file.sha256.ToLowerInvariant()) {
            $bad += "$($file.name) - wrong hash"
        }
    }
    return $bad
}

function Save-InstalledState($ValheimPath, $Manifest) {
    $Manifest | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ValheimPath $LocalManifestName) -Encoding UTF8
    @(
        "TDC Valheim Pack"
        "Version=$($Manifest.packVersion)"
        "Installed=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ) | Set-Content (Join-Path $ValheimPath $VersionFileName) -Encoding UTF8
}

function Install-OrUpdate($ValheimPath, $Manifest) {
    $old = Get-InstalledManifest $ValheimPath
    $installedVersion = if ($old) { $old.packVersion } else { "Not installed" }

    Write-Host ""
    Write-Host "Installed pack: $installedVersion"
    Write-Host "Repository pack: $($Manifest.packVersion)"
    Write-Host ""
    $confirm = Read-Host "Install/update TDC pack $($Manifest.packVersion)? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') { return }

    $backup = Backup-TDC $ValheimPath
    Write-Host "Backup: $backup"

    # Downloads are verified before they become live files one at a time.
    # If an error occurs, the backup location is shown to the user.
    Remove-OldManagedFiles $ValheimPath $old

    foreach ($file in $Manifest.files) {
        Install-File $ValheimPath $file
    }

    $bad = Verify-Pack $ValheimPath $Manifest
    if ($bad.Count -gt 0) {
        throw "Verification failed: $($bad -join '; ')"
    }

    Save-InstalledState $ValheimPath $Manifest
    Write-Host ""
    Write-Host "TDC Valheim Pack $($Manifest.packVersion) installed and verified." -ForegroundColor Green
}

function Verify-Repair($ValheimPath, $Manifest) {
    Write-Host "Verifying TDC-managed files..."
    $bad = Verify-Pack $ValheimPath $Manifest

    if ($bad.Count -eq 0) {
        Write-Host "All TDC-managed files match the repository manifest." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Problems found:" -ForegroundColor Yellow
    $bad | ForEach-Object { Write-Host " - $_" }
    Write-Host ""
    $repair = Read-Host "Repair using the repository versions? (Y/N)"
    if ($repair -match '^[Yy]$') {
        Backup-TDC $ValheimPath | Out-Null
        foreach ($file in $Manifest.files) {
            $dest = Join-Path $ValheimPath $file.destination
            $needsRepair = $true
            if (Test-Path $dest -PathType Leaf) {
                $needsRepair = ((Get-FileSha256 $dest) -ne $file.sha256.ToLowerInvariant())
            }
            if ($needsRepair) { Install-File $ValheimPath $file }
        }
        $bad2 = Verify-Pack $ValheimPath $Manifest
        if ($bad2.Count -gt 0) { throw "Repair verification failed." }
        Save-InstalledState $ValheimPath $Manifest
        Write-Host "Repair complete." -ForegroundColor Green
    }
}

function Restore-Backup($ValheimPath) {
    $root = Join-Path $ValheimPath $BackupFolderName
    if (-not (Test-Path $root)) {
        Write-Host "No TDC backups found." -ForegroundColor Yellow
        return
    }

    $backups = @(Get-ChildItem $root -Directory | Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Host "No TDC backups found." -ForegroundColor Yellow
        return
    }

    Write-Host "Available backups:"
    for ($i=0; $i -lt $backups.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i+1), $backups[$i].Name)
    }

    $choice = Read-Host "Backup number to restore (or Enter to cancel)"
    if (-not $choice) { return }
    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $backups.Count) {
        Write-Host "Invalid selection." -ForegroundColor Yellow
        return
    }

    $selected = $backups[$n-1]
    $confirm = Read-Host "Restore $($selected.Name)? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') { return }

    Copy-Item (Join-Path $selected.FullName "*") $ValheimPath -Recurse -Force
    Write-Host "Backup restored." -ForegroundColor Green
}

function Uninstall-TDC($ValheimPath) {
    $old = Get-InstalledManifest $ValheimPath
    if (-not $old) {
        Write-Host "No installed TDC manifest was found." -ForegroundColor Yellow
        return
    }

    $confirm = Read-Host "Remove files managed by TDC pack $($old.packVersion)? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') { return }

    Backup-TDC $ValheimPath | Out-Null
    Remove-OldManagedFiles $ValheimPath $old
    Remove-Item (Join-Path $ValheimPath $LocalManifestName) -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $ValheimPath $VersionFileName) -Force -ErrorAction SilentlyContinue
    Write-Host "TDC-managed files removed. Unrelated files were left alone." -ForegroundColor Green
}

try {
    Write-Header
    $ValheimPath = Get-ValheimPath
    Write-Host "[OK] Valheim: $ValheimPath" -ForegroundColor Green
    $Manifest = Get-RemoteManifest

    while ($true) {
        Write-Header
        $installed = Get-InstalledManifest $ValheimPath
        $installedVersion = if ($installed) { $installed.packVersion } else { "Not installed" }

        Write-Host "Valheim:       $ValheimPath"
        Write-Host "Installed TDC: $installedVersion"
        Write-Host "Repository:    $($Manifest.packVersion)"
        Write-Host ""
        Write-Host "[1] Install / Update"
        Write-Host "[2] Verify / Repair"
        Write-Host "[3] Restore Backup"
        Write-Host "[4] Uninstall TDC Pack"
        Write-Host "[5] Refresh Repository Manifest"
        Write-Host "[6] Exit"
        Write-Host ""

        switch (Read-Host "Select") {
            "1" { Install-OrUpdate $ValheimPath $Manifest }
            "2" { Verify-Repair $ValheimPath $Manifest }
            "3" { Restore-Backup $ValheimPath }
            "4" { Uninstall-TDC $ValheimPath }
            "5" { $Manifest = Get-RemoteManifest; Write-Host "Manifest refreshed." -ForegroundColor Green }
            "6" { exit 0 }
            default { Write-Host "Invalid selection." -ForegroundColor Yellow }
        }
        Write-Host ""
        Read-Host "Press Enter to continue" | Out-Null
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "No further changes will be made."
    exit 1
}
