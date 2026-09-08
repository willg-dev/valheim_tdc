$ErrorActionPreference = "Stop"

$RepoOwner = "willg-dev"
$RepoName = "valheim_tdc"
$Branch = "main"
$ManifestUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/manifest.json"
$ArchiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"

$StateName = "TDCValheimPack.manifest.json"
$VersionName = "TDCValheimPack.version"
$BackupName = "TDCModpackBackups"

function Show-Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host "                 TDC VALHEIM INSTALLER v0.7.1"
    Write-Host "============================================================"
    Write-Host ""
}

function Get-ValheimPath {
    $candidates = @()
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\Valheim" }
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles "Steam\steamapps\common\Valheim" }

    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath).SteamPath
        if ($steamPath) {
            $candidates += Join-Path $steamPath "steamapps\common\Valheim"
            $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $matches = (Select-String $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches
                foreach ($match in $matches) {
                    $library = $match.Groups[1].Value -replace '\\\\', '\'
                    $candidates += Join-Path $library "steamapps\common\Valheim"
                }
            }
        }
    } catch {}

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path (Join-Path $candidate "valheim.exe")) { return $candidate }
    }

    Write-Host "Valheim was not found automatically." -ForegroundColor Yellow
    $manual = (Read-Host "Paste the Valheim folder path").Trim('"')
    if (-not (Test-Path (Join-Path $manual "valheim.exe"))) { throw "valheim.exe was not found." }
    return $manual
}

function Get-RemoteManifest {
    return Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
}

function Get-InstalledManifest {
    param([string]$GamePath)
    $path = Join-Path $GamePath $StateName
    if (Test-Path $path) {
        try { return Get-Content $path -Raw | ConvertFrom-Json } catch {}
    }
    return $null
}

function Test-BepInExInstalled {
    param([string]$GamePath)
    return ((Test-Path (Join-Path $GamePath "BepInEx")) -and (Test-Path (Join-Path $GamePath "winhttp.dll")))
}

function Test-BepInExInitialized {
    param([string]$GamePath)
    $log = Join-Path $GamePath "BepInEx\LogOutput.log"
    if (-not (Test-Path $log -PathType Leaf)) { return $false }
    return (Get-Item $log).Length -gt 0
}

function Get-RepositorySnapshot {
    $temp = Join-Path $env:TEMP ("tdc_" + [guid]::NewGuid().ToString("N"))
    $zip = "$temp.zip"
    Write-Host "Downloading current TDC repository snapshot..."
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $temp -Force
    $repoRoot = Get-ChildItem $temp -Directory | Select-Object -First 1
    if (-not $repoRoot) { throw "Repository archive was empty." }
    return @{ Temp=$temp; Zip=$zip; Root=$repoRoot.FullName }
}

function Remove-Snapshot {
    param($Snapshot)
    if ($Snapshot) {
        Remove-Item $Snapshot.Zip -Force -ErrorAction SilentlyContinue
        Remove-Item $Snapshot.Temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-PackageFileMap {
    param($RemoteManifest, $Snapshot, [bool]$BootstrapOnly=$false)

    $map = @()
    if ($BootstrapOnly) {
        $packages = @($RemoteManifest.packages | Where-Object { $_.stage -eq "bootstrap" -and $_.target -ne "server" })
    } else {
        $packages = @($RemoteManifest.packages | Where-Object { $_.target -ne "server" })
    }

    foreach ($package in $packages) {
        $sourceRoot = Join-Path $Snapshot.Root $package.source
        if (-not (Test-Path $sourceRoot)) { throw "Repository package '$($package.source)' was not found." }

        $include = @()
        $exclude = @()

        if ($null -ne $package.PSObject.Properties["include"]) {
            $include = @($package.include | Where-Object { $null -ne $_ -and $_ -ne "" })
        }
        if ($null -ne $package.PSObject.Properties["exclude"]) {
            $exclude = @($package.exclude | Where-Object { $null -ne $_ -and $_ -ne "" })
        }

        $packageFileCount = 0
        foreach ($file in (Get-ChildItem $sourceRoot -File -Recurse)) {
            $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\','/')
            $copy = ($include.Count -eq 0)

            foreach ($pattern in $include) {
                if ($pattern -and (($relative -like $pattern) -or ($file.Name -like $pattern))) { $copy = $true }
            }
            foreach ($pattern in $exclude) {
                if ($pattern -and (($relative -like $pattern) -or ($file.Name -like $pattern))) { $copy = $false }
            }
            if (-not $copy) { continue }

            if ($package.destination -eq ".") { $destination = $relative }
            else { $destination = Join-Path $package.destination $relative }

            $map += [pscustomobject]@{
                Package = $package.name
                Source = $file.FullName
                Destination = $destination
                Hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
            }
            $packageFileCount++
        }

        if ($packageFileCount -eq 0) {
            throw "Package '$($package.name)' resolved to 0 installable files. Installation stopped."
        }
    }

    if ($map.Count -eq 0) {
        throw "The TDC repository resolved to 0 installable files. Installation stopped."
    }
    return $map
}

function Backup-TDCPack {
    param([string]$GamePath)
    $backup = Join-Path (Join-Path $GamePath $BackupName) (Get-Date -Format "yyyyMMdd_HHmmss")
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    $state = Get-InstalledManifest -GamePath $GamePath
    if ($state -and $state.managedFiles) {
        foreach ($relative in $state.managedFiles) {
            $source = Join-Path $GamePath $relative
            if (Test-Path $source -PathType Leaf) {
                $destination = Join-Path $backup $relative
                New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
                Copy-Item $source $destination -Force
            }
        }
    }

    foreach ($name in @($StateName,$VersionName)) {
        $source = Join-Path $GamePath $name
        if (Test-Path $source) { Copy-Item $source $backup -Force }
    }
    return $backup
}

function Save-State {
    param([string]$GamePath, $RemoteManifest, $FileMap)

    $managed = @()
    foreach ($item in $FileMap) {
        $managed += [ordered]@{
            path = $item.Destination
            sha256 = $item.Hash
            package = $item.Package
        }
    }

    $state = [ordered]@{
        packName = $RemoteManifest.packName
        packVersion = $RemoteManifest.packVersion
        installed = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        managedFiles = $managed
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $GamePath $StateName) -Encoding UTF8
    "TDC Valheim Pack`nVersion=$($RemoteManifest.packVersion)" | Set-Content (Join-Path $GamePath $VersionName) -Encoding UTF8
}

function Sync-FileMap {
    param([string]$GamePath, $FileMap)

    foreach ($item in $FileMap) {
        $destination = Join-Path $GamePath $item.Destination
        $needsCopy = $true

        if (Test-Path $destination -PathType Leaf) {
            $localHash = (Get-FileHash -Path $destination -Algorithm SHA256).Hash
            if ($localHash -eq $item.Hash) { $needsCopy = $false }
        }

        if ($needsCopy) {
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
            Copy-Item $item.Source $destination -Force
            Write-Host "[SYNC] $($item.Destination)" -ForegroundColor Cyan
        } else {
            Write-Host "[OK]   $($item.Destination)" -ForegroundColor DarkGray
        }
    }
}

function Compare-WithRepository {
    param([string]$GamePath, $FileMap)

    $results = @()
    foreach ($item in $FileMap) {
        $local = Join-Path $GamePath $item.Destination
        if (-not (Test-Path $local -PathType Leaf)) {
            $status = "MISSING"
        } else {
            $localHash = (Get-FileHash -Path $local -Algorithm SHA256).Hash
            if ($localHash -eq $item.Hash) { $status = "OK" } else { $status = "HASH MISMATCH" }
        }

        $results += [pscustomobject]@{
            Package = $item.Package
            Path = $item.Destination
            Status = $status
        }
    }
    return $results
}

function Assert-BepInExBootstrap {
    param([string]$GamePath)

    $required = @("BepInEx", "doorstop_libs", "doorstop_config.ini", "winhttp.dll")
    $missing = @()

    foreach ($relative in $required) {
        if (-not (Test-Path (Join-Path $GamePath $relative))) {
            $missing += $relative
        }
    }

    if ($missing.Count -gt 0) {
        throw "BepInEx bootstrap validation failed. Missing: $($missing -join ', ')"
    }

    Write-Host ""
    Write-Host "BepInEx bootstrap validation:" -ForegroundColor Cyan
    foreach ($relative in $required) {
        Write-Host "[OK] $relative" -ForegroundColor Green
    }
}

function Install-TDCPack {
    param([string]$GamePath, $RemoteManifest)

    $bootstrapOnly = -not (Test-BepInExInitialized -GamePath $GamePath)

    if ($bootstrapOnly) {
        Write-Host ""
        Write-Host "FIRST LAUNCH REQUIRED - installing BepInEx bootstrap only." -ForegroundColor Yellow
    } else {
        Write-Host "BepInEx initialization detected." -ForegroundColor Green
    }

    if ((Read-Host "Continue with TDC synchronization? (Y/N)") -notmatch '^[Yy]$') { return }

    $backup = Backup-TDCPack -GamePath $GamePath
    Write-Host "Backup: $backup"

    $snapshot = $null
    try {
        $snapshot = Get-RepositorySnapshot
        $map = Get-PackageFileMap -RemoteManifest $RemoteManifest -Snapshot $snapshot -BootstrapOnly $bootstrapOnly
        Sync-FileMap -GamePath $GamePath -FileMap $map

        if ($bootstrapOnly) {
            Assert-BepInExBootstrap -GamePath $GamePath
        }

        Save-State -GamePath $GamePath -RemoteManifest $RemoteManifest -FileMap $map
    }
    finally { Remove-Snapshot -Snapshot $snapshot }

    if ($bootstrapOnly) {
        Write-Host ""
        Write-Host "FIRST LAUNCH REQUIRED" -ForegroundColor Yellow
        Write-Host "Launch Valheim through Steam, reach the main menu, close Valheim,"
        Write-Host "then run RUN-TDC-Valheim-Installer.bat again."
    } else {
        Write-Host ""
        Write-Host "TDC pack synchronized successfully." -ForegroundColor Green
    }
}

function Verify-Repair {
    param([string]$GamePath, $RemoteManifest)

    $snapshot = $null
    try {
        $snapshot = Get-RepositorySnapshot
        $bootstrapOnly = -not (Test-BepInExInitialized -GamePath $GamePath)
        $map = Get-PackageFileMap -RemoteManifest $RemoteManifest -Snapshot $snapshot -BootstrapOnly $bootstrapOnly
        $results = Compare-WithRepository -GamePath $GamePath -FileMap $map

        Write-Host ""
        Write-Host "TDC PACK VERIFICATION"
        Write-Host "------------------------------------------------------------"

        $problems = @()
        foreach ($result in $results) {
            if ($result.Status -eq "OK") {
                Write-Host "[OK]       $($result.Path)" -ForegroundColor Green
            } else {
                Write-Host "[$($result.Status)] $($result.Path)" -ForegroundColor Yellow
                $problems += $result
            }
        }

        Write-Host ""
        if ($problems.Count -eq 0) {
            Write-Host "All $($results.Count) TDC-managed files match GitHub." -ForegroundColor Green
            return
        }

        Write-Host "$($problems.Count) file(s) differ from the current GitHub pack." -ForegroundColor Yellow

        if ((Read-Host "Repair them now? (Y/N)") -match '^[Yy]$') {
            $backup = Backup-TDCPack -GamePath $GamePath
            Write-Host "Backup: $backup"
            Sync-FileMap -GamePath $GamePath -FileMap $map
            Save-State -GamePath $GamePath -RemoteManifest $RemoteManifest -FileMap $map
            Write-Host "Repair complete." -ForegroundColor Green
        }
    }
    finally { Remove-Snapshot -Snapshot $snapshot }
}

try {
    $gamePath = Get-ValheimPath
    $remoteManifest = Get-RemoteManifest

    while ($true) {
        Show-Header
        $installed = Get-InstalledManifest -GamePath $gamePath
        $installedVersion = if ($installed) { $installed.packVersion } else { "Not installed" }
        $bepInstalled = if (Test-BepInExInstalled -GamePath $gamePath) { "Installed" } else { "Not installed" }
        $bepSetup = if (Test-BepInExInitialized -GamePath $gamePath) { "Complete" } else { "FIRST LAUNCH REQUIRED" }

        Write-Host "Valheim:        $gamePath"
        Write-Host "BepInEx:        $bepInstalled"
        Write-Host "BepInEx Setup:  $bepSetup"
        Write-Host "Installed TDC:  $installedVersion"
        Write-Host "Repository:     $($remoteManifest.packVersion)"
        Write-Host ""
        Write-Host "[1] Install / Update"
        Write-Host "[2] Verify / Repair"
        Write-Host "[3] Refresh Repository"
        Write-Host "[4] Exit"
        Write-Host ""

        switch (Read-Host "Select") {
            "1" { Install-TDCPack -GamePath $gamePath -RemoteManifest $remoteManifest }
            "2" { Verify-Repair -GamePath $gamePath -RemoteManifest $remoteManifest }
            "3" {
                $remoteManifest = Get-RemoteManifest
                Write-Host "Repository manifest refreshed." -ForegroundColor Green
            }
            "4" { exit 0 }
            default { Write-Host "Invalid selection." }
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
