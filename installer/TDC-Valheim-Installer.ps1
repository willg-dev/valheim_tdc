$ErrorActionPreference = "Stop"

$RepoOwner = "willg-dev"
$RepoName  = "valheim_tdc"
$Branch    = "main"
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$ManifestUrl = "$RawBase/manifest.json"

$LocalManifestName = "TDCValheimPack.manifest.json"
$VersionFileName   = "TDCValheimPack.version"
$BackupFolderName  = "TDCModpackBackups"

function Header {
    Clear-Host
    Write-Host "============================================================"
    Write-Host "                 TDC VALHEIM INSTALLER"
    Write-Host "============================================================"
    Write-Host ""
}

function Get-ValheimPath {
    $candidates = @()
    if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\Valheim" }
    if ($env:ProgramFiles) { $candidates += Join-Path $env:ProgramFiles "Steam\steamapps\common\Valheim" }

    try {
        $steam = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath).SteamPath
        if ($steam) {
            $candidates += Join-Path $steam "steamapps\common\Valheim"
            $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                foreach ($m in (Select-String $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches) {
                    $lib = $m.Groups[1].Value -replace '\\\\','\'
                    $candidates += Join-Path $lib "steamapps\common\Valheim"
                }
            }
        }
    } catch {}

    foreach ($p in ($candidates | Select-Object -Unique)) {
        if (Test-Path (Join-Path $p "valheim.exe")) { return $p }
    }

    Write-Host "Valheim was not found automatically." -ForegroundColor Yellow
    Write-Host "Steam > Library > Valheim > Manage > Browse local files"
    $p = (Read-Host "Paste the Valheim folder path").Trim('"')
    if (-not (Test-Path (Join-Path $p "valheim.exe"))) { throw "valheim.exe not found at '$p'." }
    return $p
}

function Remote-Manifest {
    Write-Host "Reading TDC manifest from GitHub..."
    return Invoke-RestMethod -Uri $ManifestUrl -UseBasicParsing
}

function Installed-Manifest($Game) {
    $p = Join-Path $Game $LocalManifestName
    if (Test-Path $p) {
        try { return Get-Content $p -Raw | ConvertFrom-Json } catch {}
    }
    return $null
}

function Backup-Pack($Game) {
    $dest = Join-Path $Game ("$BackupFolderName\" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    New-Item -ItemType Directory $dest -Force | Out-Null
    foreach ($x in @("BepInEx","doorstop_libs","winhttp.dll","doorstop_config.ini","changelog.txt",$LocalManifestName,$VersionFileName)) {
        $src = Join-Path $Game $x
        if (Test-Path $src) { Copy-Item $src $dest -Recurse -Force }
    }
    return $dest
}

function Remove-Managed($Game,$Old) {
    if (-not $Old -or -not $Old.managedFiles) { return }
    Write-Host "Removing files owned by the previous TDC pack..."
    foreach ($rel in $Old.managedFiles) {
        $p = Join-Path $Game $rel
        if (Test-Path $p -PathType Leaf) { Remove-Item $p -Force }
    }
}

function Install-GitHubFolder($Game,$Package,[ref]$Managed) {
    $archiveUrl = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
    $tmpRoot = Join-Path $env:TEMP ("tdc_" + [guid]::NewGuid().ToString("N"))
    $zip = "$tmpRoot.zip"
    try {
        Write-Host "Downloading $($Package.name) from TDC GitHub..."
        Invoke-WebRequest $archiveUrl -OutFile $zip -UseBasicParsing
        Expand-Archive $zip $tmpRoot -Force

        $repoRoot = Get-ChildItem $tmpRoot -Directory | Select-Object -First 1
        if (-not $repoRoot) { throw "Downloaded repository archive was empty." }

        $source = Join-Path $repoRoot.FullName $Package.source
        if (-not (Test-Path $source)) { throw "Repository folder '$($Package.source)' was not found." }

        $exclude = @($Package.exclude)
        $files = Get-ChildItem $source -File -Recurse

        foreach ($f in $files) {
            $relative = $f.FullName.Substring($source.Length).TrimStart('\','/')
            $skip = $false
            foreach ($pattern in $exclude) {
                if ($pattern -and ($relative -like $pattern -or $f.Name -like $pattern)) { $skip = $true; break }
            }
            if ($skip) { continue }

            $dest = Join-Path $Game $relative
            New-Item -ItemType Directory (Split-Path $dest -Parent) -Force | Out-Null
            Copy-Item $f.FullName $dest -Force
            $Managed.Value += $relative
        }
        Write-Host "[OK] $($Package.name)" -ForegroundColor Green
    }
    finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-File($Game,$File,[ref]$Managed) {
    $tmp = Join-Path $env:TEMP ("tdc_" + [guid]::NewGuid().ToString("N"))
    try {
        Write-Host "Downloading $($File.name)..."
        Invoke-WebRequest $File.url -OutFile $tmp -UseBasicParsing
        if ($File.sha256) {
            $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actual -ne $File.sha256.ToLowerInvariant()) { throw "SHA-256 mismatch for $($File.name)." }
        }
        $dest = Join-Path $Game $File.destination
        New-Item -ItemType Directory (Split-Path $dest -Parent) -Force | Out-Null
        Copy-Item $tmp $dest -Force
        $Managed.Value += $File.destination
        Write-Host "[OK] $($File.name)" -ForegroundColor Green
    }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Save-State($Game,$Remote,$Managed) {
    $state = [ordered]@{
        packName = $Remote.packName
        packVersion = $Remote.packVersion
        installed = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        managedFiles = @($Managed | Sort-Object -Unique)
    }
    $state | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Game $LocalManifestName) -Encoding UTF8
    @("TDC Valheim Pack","Version=$($Remote.packVersion)") | Set-Content (Join-Path $Game $VersionFileName) -Encoding UTF8
}

function Install-Pack($Game,$Remote) {
    $old = Installed-Manifest $Game
    $oldVersion = if ($old) {$old.packVersion} else {"Not installed"}
    Write-Host "Installed: $oldVersion"
    Write-Host "Available: $($Remote.packVersion)"
    if ((Read-Host "Install/update? (Y/N)") -notmatch '^[Yy]$') { return }

    $backup = Backup-Pack $Game
    Write-Host "Backup: $backup"
    Remove-Managed $Game $old

    $managed = @()
    foreach ($pkg in @($Remote.packages)) {
        if ($pkg.type -eq "githubFolder") { Install-GitHubFolder $Game $pkg ([ref]$managed) }
        elseif ($pkg.type -eq "file") { Install-File $Game $pkg ([ref]$managed) }
        else { throw "Unknown package type '$($pkg.type)'." }
    }

    Save-State $Game $Remote $managed
    Write-Host ""
    Write-Host "TDC Valheim Pack $($Remote.packVersion) installed." -ForegroundColor Green
    Write-Host "$($managed.Count) managed files recorded."
}

function Verify-Pack($Game) {
    $old = Installed-Manifest $Game
    if (-not $old) { Write-Host "TDC is not installed." -ForegroundColor Yellow; return }
    $missing = @()
    foreach ($rel in $old.managedFiles) {
        if (-not (Test-Path (Join-Path $Game $rel) -PathType Leaf)) { $missing += $rel }
    }
    if ($missing.Count -eq 0) {
        Write-Host "All $($old.managedFiles.Count) TDC-managed files are present." -ForegroundColor Green
    } else {
        Write-Host "$($missing.Count) managed file(s) are missing:" -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host " - $_" }
        Write-Host "Choose Install/Update to reinstall the current repository pack."
    }
}

function Restore-Pack($Game) {
    $root = Join-Path $Game $BackupFolderName
    $list = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($list.Count -eq 0) { Write-Host "No backups found."; return }
    for ($i=0;$i -lt $list.Count;$i++) { Write-Host "[$($i+1)] $($list[$i].Name)" }
    $choice = Read-Host "Backup number (Enter cancels)"
    if (-not $choice) { return }
    $n=0
    if (-not [int]::TryParse($choice,[ref]$n) -or $n -lt 1 -or $n -gt $list.Count) { Write-Host "Invalid selection."; return }
    if ((Read-Host "Restore $($list[$n-1].Name)? (Y/N)") -notmatch '^[Yy]$') { return }
    Copy-Item (Join-Path $list[$n-1].FullName "*") $Game -Recurse -Force
    Write-Host "Backup restored." -ForegroundColor Green
}

function Uninstall-Pack($Game) {
    $old = Installed-Manifest $Game
    if (-not $old) { Write-Host "TDC is not installed."; return }
    if ((Read-Host "Remove all TDC-managed files? (Y/N)") -notmatch '^[Yy]$') { return }
    Backup-Pack $Game | Out-Null
    Remove-Managed $Game $old
    Remove-Item (Join-Path $Game $LocalManifestName) -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $Game $VersionFileName) -Force -ErrorAction SilentlyContinue
    Write-Host "TDC-managed files removed." -ForegroundColor Green
}

try {
    Header
    $Game = Get-ValheimPath
    $Remote = Remote-Manifest

    while ($true) {
        Header
        $old = Installed-Manifest $Game
        $installed = if ($old) {$old.packVersion} else {"Not installed"}
        Write-Host "Valheim:       $Game"
        Write-Host "Installed TDC: $installed"
        Write-Host "Repository:    $($Remote.packVersion)"
        Write-Host ""
        Write-Host "[1] Install / Update"
        Write-Host "[2] Verify"
        Write-Host "[3] Restore Backup"
        Write-Host "[4] Uninstall TDC Pack"
        Write-Host "[5] Refresh Repository"
        Write-Host "[6] Exit"
        Write-Host ""
        switch (Read-Host "Select") {
            "1" { Install-Pack $Game $Remote }
            "2" { Verify-Pack $Game }
            "3" { Restore-Pack $Game }
            "4" { Uninstall-Pack $Game }
            "5" { $Remote = Remote-Manifest; Write-Host "Manifest refreshed." -ForegroundColor Green }
            "6" { exit 0 }
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
