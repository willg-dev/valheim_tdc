$ErrorActionPreference="Stop"
$Owner="willg-dev"; $Repo="valheim_tdc"; $Branch="main"
$Raw="https://raw.githubusercontent.com/$Owner/$Repo/$Branch"
$ManifestUrl="$Raw/manifest.json"
$StateName="TDCValheimPack.manifest.json"; $VersionName="TDCValheimPack.version"; $BackupName="TDCModpackBackups"

function Header { Clear-Host; Write-Host "============================================================"; Write-Host "                 TDC VALHEIM INSTALLER v0.6"; Write-Host "============================================================"; Write-Host "" }
function GamePath {
 $c=@()
 if(${env:ProgramFiles(x86)}){$c+=Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\Valheim"}
 if($env:ProgramFiles){$c+=Join-Path $env:ProgramFiles "Steam\steamapps\common\Valheim"}
 try{$s=(Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name SteamPath).SteamPath
  if($s){$c+=Join-Path $s "steamapps\common\Valheim";$v=Join-Path $s "steamapps\libraryfolders.vdf"
   if(Test-Path $v){foreach($m in(Select-String $v -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches){$l=$m.Groups[1].Value-replace'\\\\','\';$c+=Join-Path $l "steamapps\common\Valheim"}}}}catch{}
 foreach($p in($c|Select-Object -Unique)){if(Test-Path(Join-Path $p "valheim.exe")){return $p}}
 $p=(Read-Host "Paste Valheim folder path").Trim('"');if(-not(Test-Path(Join-Path $p "valheim.exe"))){throw "valheim.exe not found."};return $p
}
function Remote { Invoke-RestMethod $ManifestUrl -UseBasicParsing }
function State($g){$p=Join-Path $g $StateName;if(Test-Path $p){try{return Get-Content $p -Raw|ConvertFrom-Json}catch{}};return $null}
function BepOK($g){$p=Join-Path $g "BepInEx\LogOutput.log";return(Test-Path $p -PathType Leaf)-and((Get-Item $p).Length-gt 0)}
function Backup($g){$d=Join-Path $g("$BackupName\"+(Get-Date -Format "yyyyMMdd_HHmmss"));New-Item -ItemType Directory $d -Force|Out-Null
 foreach($x in@("BepInEx","doorstop_libs","winhttp.dll","doorstop_config.ini","changelog.txt",$StateName,$VersionName)){$s=Join-Path $g $x;if(Test-Path $s){Copy-Item $s $d -Recurse -Force}};return $d}
function RemoveOwned($g,$old){if($old -and $old.managedFiles){foreach($r in $old.managedFiles){$p=Join-Path $g $r;if(Test-Path $p -PathType Leaf){Remove-Item $p -Force}}}}
function RepoSnapshot {
 $t=Join-Path $env:TEMP("tdc_"+[guid]::NewGuid().ToString("N"));$z="$t.zip"
 Invoke-WebRequest "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip" -OutFile $z -UseBasicParsing
 Expand-Archive $z $t -Force;$rr=Get-ChildItem $t -Directory|Select-Object -First 1
 if(-not $rr){throw "Repository archive empty."}
 return @{Temp=$t;Zip=$z;Root=$rr.FullName}
}
function CopyPackage($g,$pkg,$snap,[ref]$managed){
 $src=Join-Path $snap.Root $pkg.source;if(-not(Test-Path $src)){throw "Missing repository package: $($pkg.source)"}
 $inc=@($pkg.include);$exc=@($pkg.exclude)
 foreach($f in Get-ChildItem $src -File -Recurse){
  $rel=$f.FullName.Substring($src.Length).TrimStart('\','/')
  $ok=($inc.Count-eq 0);foreach($pat in $inc){if($pat-and($rel-like $pat-or$f.Name-like $pat)){$ok=$true}}
  foreach($pat in $exc){if($pat-and($rel-like $pat-or$f.Name-like $pat)){$ok=$false}}
  if(-not $ok){continue}
  $destRel=if($pkg.destination -eq "."){$rel}else{Join-Path $pkg.destination $rel}
  $dest=Join-Path $g $destRel;New-Item -ItemType Directory(Split-Path $dest -Parent)-Force|Out-Null;Copy-Item $f.FullName $dest -Force
  $managed.Value+=$destRel
 }
 Write-Host "[OK] $($pkg.name)" -ForegroundColor Green
}
function Save($g,$m,$managed){
 [ordered]@{packName=$m.packName;packVersion=$m.packVersion;installed=(Get-Date -Format "yyyy-MM-dd HH:mm:ss");managedFiles=@($managed|Sort-Object -Unique)}|ConvertTo-Json -Depth 10|Set-Content(Join-Path $g $StateName)-Encoding UTF8
 "TDC Valheim Pack`nVersion=$($m.packVersion)"|Set-Content(Join-Path $g $VersionName)-Encoding UTF8
}
function Install($g,$m){
 $old=State $g;$initialized=BepOK $g
 if(-not $initialized){Write-Host "FIRST LAUNCH REQUIRED: installing BepInEx only." -ForegroundColor Yellow;if((Read-Host "Continue? (Y/N)")-notmatch'^[Yy]$'){return}
  $snap=RepoSnapshot;try{$managed=@();foreach($p in @($m.packages|Where-Object{$_.stage-eq"bootstrap"})){CopyPackage $g $p $snap ([ref]$managed)}
   if($old -and $old.managedFiles){$managed+=@($old.managedFiles)};Save $g $m $managed}finally{Remove-Item $snap.Zip -Force -ErrorAction SilentlyContinue;Remove-Item $snap.Temp -Recurse -Force -ErrorAction SilentlyContinue}
  Write-Host "`nBepInEx installed. Launch Valheim through Steam, reach the main menu, close it, then run this installer again." -ForegroundColor Yellow;return}
 Write-Host "BepInEx initialization detected." -ForegroundColor Green
 if((Read-Host "Install/update full TDC client pack $($m.packVersion)? (Y/N)")-notmatch'^[Yy]$'){return}
 Write-Host "Backup: $(Backup $g)";RemoveOwned $g $old;$snap=RepoSnapshot
 try{$managed=@();foreach($p in @($m.packages|Where-Object{$_.target-ne"server"})){CopyPackage $g $p $snap ([ref]$managed)};Save $g $m $managed}
 finally{Remove-Item $snap.Zip -Force -ErrorAction SilentlyContinue;Remove-Item $snap.Temp -Recurse -Force -ErrorAction SilentlyContinue}
 Write-Host "`nTDC client pack $($m.packVersion) installed." -ForegroundColor Green
}
function Verify($g){$s=State $g;if(-not$s){Write-Host "TDC not installed.";return};$miss=@();foreach($r in$s.managedFiles){if(-not(Test-Path(Join-Path $g $r)-PathType Leaf)){$miss+=$r}}
 if($miss.Count){Write-Host "$($miss.Count) managed files missing:" -ForegroundColor Yellow;$miss|%{Write-Host " - $_"}}else{Write-Host "All $($s.managedFiles.Count) managed files present." -ForegroundColor Green}}
try{$g=GamePath;$m=Remote;while($true){Header;$s=State $g;$iv=if($s){$s.packVersion}else{"Not installed"};$bi=if(Test-Path(Join-Path $g "winhttp.dll")){"Installed"}else{"Not installed"};$bs=if(BepOK $g){"Complete"}else{"FIRST LAUNCH REQUIRED"}
 Write-Host "Valheim:        $g";Write-Host "BepInEx:        $bi";Write-Host "BepInEx Setup:  $bs";Write-Host "Installed TDC:  $iv";Write-Host "Repository:     $($m.packVersion)"
 Write-Host "`n[1] Install / Update`n[2] Verify`n[3] Refresh Repository`n[4] Exit`n"
 switch(Read-Host "Select"){"1"{Install $g $m}"2"{Verify $g}"3"{$m=Remote;Write-Host "Manifest refreshed."}"4"{exit 0}default{Write-Host "Invalid selection."}}
 Read-Host "`nPress Enter to continue"|Out-Null}}
catch{Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
