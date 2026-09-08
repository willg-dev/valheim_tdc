$ErrorActionPreference = "Stop"

$RepoOwner = "willg-dev"
$RepoName  = "valheim_tdc"
$Branch    = "main"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$ManifestUrl = "$RawBase/manifest.json"

$LocalManifestName = "TDCValheimPack.manifest.json"
$VersionFileName   = "TDCValheimPack.version"
$BackupFolderName  = "TDCModpackBackups"

function Show-Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host "                 TDC VALHEIM INSTALLER v0.6.1"
    Write-Host "============================================================"
    Write-Host ""
}

function Get-ValheimPath {
    $candidates = @()

    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\Valheim"
    }

    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "Steam\steamapps\common\Valheim"
    }

    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath).SteamPath

        if ($steamPath) {
            $candidates += Join-Path $steamPath "steamapps\common\Valheim"

            $libraryVdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"

            if (Test-Path $libraryVdf) {
                $matches = (Select-String $libraryVdf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches

                foreach ($match in $matches) {
                    $libraryPath = $match.Groups[1].Value -replace '\\\\', '\'
                    $candidates += Join-Path $libraryPath "steamapps\common\Valheim"
                }
            }
        }
    }
    catch {
        # Optional registry/library lookup.
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path (Join-Path $candidate "valheim.exe")) {
            return $candidate
        }
    }

    Write-Host "Valheim was not found automatically." -ForegroundColor Yellow
    Write-Host "Steam > Library > Valheim > Manage > Browse local files"
    $manualPath = (Read-Host "Paste the Valheim folder path").Trim('"')

    if (-not (Test-Path (Join-Path $manualPath "valheim.exe"))) {
        throw "valheim.exe was not found at '$manualPath'."
    }

    return $manualPath
}

function Get-RemoteManifest {
    Write-Host "Reading TDC manifest from GitHub..."
    return Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
}

function Get-InstalledManifest {
    param([string]$GamePath)

    $manifestPath = Join-Path $GamePath $LocalManifestName

    if (Test-Path $manifestPath) {
        try {
            return Get-Content $manifestPath -Raw | ConvertFrom-Json
        }
        catch {
            return $null
        }
    }

    return $null
}

function Test-BepInExInstalled {
    param([string]$GamePath)

    return (
        (Test-Path (Join-Path $GamePath "BepInEx")) -and
        (Test-Path (Join-Path $GamePath "winhttp.dll"))
    )
}

function Test-BepInExInitialized {
    param([string]$GamePath)

    $logPath = Join-Path $GamePath "BepInEx\LogOutput.log"

    if (-not (Test-Path $logPath -PathType Leaf)) {
        return $false
    }

    try {
        return (Get-Item $logPath).Length -gt 0
    }
    catch {
        return $false
    }
}

function Backup-TDCPack {
    param([string]$GamePath)

    $backupRoot = Join-Path $GamePath $BackupFolderName
    $backupPath = Join-Path $backupRoot (Get-Date -Format "yyyyMMdd_HHmmss")

    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null

    $itemsToBackup = @(
        "BepInEx",
        "doorstop_libs",
        "winhttp.dll",
        "doorstop_config.ini",
        "changelog.txt",
        $LocalManifestName,
        $VersionFileName
    )

    foreach ($item in $itemsToBackup) {
        $sourcePath = Join-Path $GamePath $item

        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath $backupPath -Recurse -Force
        }
    }

    return $backupPath
}

function Remove-TDCManagedFiles {
    param(
        [string]$GamePath,
        $InstalledManifest
    )

    if (-not $InstalledManifest -or -not $InstalledManifest.managedFiles) {
        return
    }

    Write-Host "Removing files owned by the previous TDC pack..."

    foreach ($relativePath in $InstalledManifest.managedFiles) {
        $fullPath = Join-Path $GamePath $relativePath

        if (Test-Path $fullPath -PathType Leaf) {
            Remove-Item $fullPath -Force
        }
    }
}

function Get-RepositorySnapshot {
    $tempRoot = Join-Path $env:TEMP ("tdc_" + [guid]::NewGuid().ToString("N"))
    $zipPath = "$tempRoot.zip"
    $archiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"

    Write-Host "Downloading TDC repository snapshot..."

    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

    $repoRoot = Get-ChildItem $tempRoot -Directory | Select-Object -First 1

    if (-not $repoRoot) {
        throw "Downloaded repository archive was empty."
    }

    return @{
        Temp = $tempRoot
        Zip  = $zipPath
        Root = $repoRoot.FullName
    }
}

function Copy-RepositoryPackage {
    param(
        [string]$GamePath,
        $Package,
        $Snapshot,
        [ref]$ManagedFiles
    )

    $sourceRoot = Join-Path $Snapshot.Root $Package.source

    if (-not (Test-Path $sourceRoot)) {
        throw "Repository package '$($Package.source)' was not found."
    }

    $includePatterns = @($Package.include)
    $excludePatterns = @($Package.exclude)
    $sourceFiles = Get-ChildItem $sourceRoot -File -Recurse

    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $shouldCopy = ($includePatterns.Count -eq 0)

        foreach ($pattern in $includePatterns) {
            if ($pattern -and (($relativePath -like $pattern) -or ($file.Name -like $pattern))) {
                $shouldCopy = $true
            }
        }

        foreach ($pattern in $excludePatterns) {
            if ($pattern -and (($relativePath -like $pattern) -or ($file.Name -like $pattern))) {
                $shouldCopy = $false
            }
        }

        if (-not $shouldCopy) {
            continue
        }

        if ($Package.destination -eq ".") {
            $destinationRelativePath = $relativePath
        }
        else {
            $destinationRelativePath = Join-Path $Package.destination $relativePath
        }

        $destinationPath = Join-Path $GamePath $destinationRelativePath
        $destinationDirectory = Split-Path $destinationPath -Parent

        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item $file.FullName $destinationPath -Force
        $ManagedFiles.Value += $destinationRelativePath
    }

    Write-Host "[OK] $($Package.name)" -ForegroundColor Green
}

function Save-TDCState {
    param(
        [string]$GamePath,
        $RemoteManifest,
        $ManagedFiles
    )

    $state = [ordered]@{
        packName     = $RemoteManifest.packName
        packVersion  = $RemoteManifest.packVersion
        installed    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        managedFiles = @($ManagedFiles | Sort-Object -Unique)
    }

    $state |
        ConvertTo-Json -Depth 10 |
        Set-Content (Join-Path $GamePath $LocalManifestName) -Encoding UTF8

    @(
        "TDC Valheim Pack"
        "Version=$($RemoteManifest.packVersion)"
    ) | Set-Content (Join-Path $GamePath $VersionFileName) -Encoding UTF8
}

function Install-TDCPack {
    param(
        [string]$GamePath,
        $RemoteManifest
    )

    $installedManifest = Get-InstalledManifest -GamePath $GamePath
    $bepInitialized = Test-BepInExInitialized -GamePath $GamePath

    if (-not $bepInitialized) {
        Write-Host ""
        Write-Host "BepInEx has not completed its first launch yet." -ForegroundColor Yellow
        Write-Host "Only the BepInEx bootstrap package will be installed."

        if ((Read-Host "Continue? (Y/N)") -notmatch '^[Yy]$') {
            return
        }

        $backupPath = Backup-TDCPack -GamePath $GamePath
        Write-Host "Backup: $backupPath"

        $snapshot = Get-RepositorySnapshot

        try {
            $managedFiles = @()

            $bootstrapPackages = @(
                $RemoteManifest.packages |
                Where-Object { $_.stage -eq "bootstrap" }
            )

            foreach ($package in $bootstrapPackages) {
                Copy-RepositoryPackage `
                    -GamePath $GamePath `
                    -Package $package `
                    -Snapshot $snapshot `
                    -ManagedFiles ([ref]$managedFiles)
            }

            if ($installedManifest -and $installedManifest.managedFiles) {
                $managedFiles += @($installedManifest.managedFiles)
            }

            Save-TDCState `
                -GamePath $GamePath `
                -RemoteManifest $RemoteManifest `
                -ManagedFiles $managedFiles
        }
        finally {
            Remove-Item $snapshot.Zip -Force -ErrorAction SilentlyContinue
            Remove-Item $snapshot.Temp -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Yellow
        Write-Host "              FIRST LAUNCH REQUIRED"
        Write-Host "============================================================" -ForegroundColor Yellow
        Write-Host "1. Close this installer."
        Write-Host "2. Launch Valheim normally through Steam."
        Write-Host "3. Wait until you reach the main menu."
        Write-Host "4. Close Valheim."
        Write-Host "5. Run the TDC installer again and choose Install / Update."
        Write-Host ""
        return
    }

    Write-Host "BepInEx initialization detected." -ForegroundColor Green

    if ((Read-Host "Install/update full TDC client pack $($RemoteManifest.packVersion)? (Y/N)") -notmatch '^[Yy]$') {
        return
    }

    $backupPath = Backup-TDCPack -GamePath $GamePath
    Write-Host "Backup: $backupPath"

    Remove-TDCManagedFiles `
        -GamePath $GamePath `
        -InstalledManifest $installedManifest

    $snapshot = Get-RepositorySnapshot

    try {
        $managedFiles = @()

        $clientPackages = @(
            $RemoteManifest.packages |
            Where-Object { $_.target -ne "server" }
        )

        foreach ($package in $clientPackages) {
            Copy-RepositoryPackage `
                -GamePath $GamePath `
                -Package $package `
                -Snapshot $snapshot `
                -ManagedFiles ([ref]$managedFiles)
        }

        Save-TDCState `
            -GamePath $GamePath `
            -RemoteManifest $RemoteManifest `
            -ManagedFiles $managedFiles
    }
    finally {
        Remove-Item $snapshot.Zip -Force -ErrorAction SilentlyContinue
        Remove-Item $snapshot.Temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "TDC client pack $($RemoteManifest.packVersion) installed." -ForegroundColor Green
    Write-Host "$($managedFiles.Count) managed files recorded."
}

function Verify-TDCPack {
    param([string]$GamePath)

    $installedManifest = Get-InstalledManifest -GamePath $GamePath

    if (-not $installedManifest) {
        Write-Host "TDC is not installed." -ForegroundColor Yellow
        return
    }

    $missingFiles = @()

    foreach ($relativePath in $installedManifest.managedFiles) {
        $fullPath = Join-Path $GamePath $relativePath

        if (-not (Test-Path $fullPath -PathType Leaf)) {
            $missingFiles += $relativePath
        }
    }

    if ($missingFiles.Count -eq 0) {
        Write-Host "All $($installedManifest.managedFiles.Count) TDC-managed files are present." -ForegroundColor Green
    }
    else {
        Write-Host "$($missingFiles.Count) managed file(s) are missing:" -ForegroundColor Yellow

        foreach ($missingFile in $missingFiles) {
            Write-Host " - $missingFile"
        }

        Write-Host ""
        Write-Host "Choose Install / Update to reinstall the current repository pack."
    }
}

try {
    $gamePath = Get-ValheimPath
    $remoteManifest = Get-RemoteManifest

    while ($true) {
        Show-Header

        $installedManifest = Get-InstalledManifest -GamePath $gamePath

        if ($installedManifest) {
            $installedVersion = $installedManifest.packVersion
        }
        else {
            $installedVersion = "Not installed"
        }

        if (Test-BepInExInstalled -GamePath $gamePath) {
            $bepInstalledStatus = "Installed"
        }
        else {
            $bepInstalledStatus = "Not installed"
        }

        if (Test-BepInExInitialized -GamePath $gamePath) {
            $bepSetupStatus = "Complete"
        }
        else {
            $bepSetupStatus = "FIRST LAUNCH REQUIRED"
        }

        Write-Host "Valheim:        $gamePath"
        Write-Host "BepInEx:        $bepInstalledStatus"
        Write-Host "BepInEx Setup:  $bepSetupStatus"
        Write-Host "Installed TDC:  $installedVersion"
        Write-Host "Repository:     $($remoteManifest.packVersion)"
        Write-Host ""
        Write-Host "[1] Install / Update"
        Write-Host "[2] Verify"
        Write-Host "[3] Refresh Repository"
        Write-Host "[4] Exit"
        Write-Host ""

        $selection = Read-Host "Select"

        switch ($selection) {
            "1" {
                Install-TDCPack `
                    -GamePath $gamePath `
                    -RemoteManifest $remoteManifest
            }

            "2" {
                Verify-TDCPack -GamePath $gamePath
            }

            "3" {
                $remoteManifest = Get-RemoteManifest
                Write-Host "Manifest refreshed." -ForegroundColor Green
            }

            "4" {
                exit 0
            }

            default {
                Write-Host "Invalid selection."
            }
        }

        Write-Host ""
        Read-Host "Press Enter to continue" | Out-Null
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
