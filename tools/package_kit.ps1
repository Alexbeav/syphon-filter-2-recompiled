param(
    [Parameter(Mandatory = $true)] [string]$CliDir,
    [Parameter(Mandatory = $true)] [string]$FrameworkRoot,
    [string]$Output = "dist/syphon-filter-2-recompiled-kit-windows-x64.zip"
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Cli = Resolve-Path $CliDir
$Framework = Resolve-Path $FrameworkRoot
$OutputPath = Join-Path $Root $Output
$StageRoot = Join-Path $Root "dist\kit-stage"
$Stage = Join-Path $StageRoot "syphon-filter-2-recompiled-kit"
$SelectedSourceBase = "e08aaff871a5c9b4a7756a6ed6fe99c98c4dbc0f"

$Dirty = (& git -C $Root status --porcelain --untracked-files=all) -join "`n"
if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace($Dirty)) {
    throw "Package generation requires a clean committed source tree."
}
$SourceCommit = (& git -C $Root rev-parse HEAD).Trim()
$SourceTree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
& git -C $Root merge-base --is-ancestor $SelectedSourceBase $SourceCommit
if ($LASTEXITCODE -ne 0) { throw "Product source does not descend from selected public base $SelectedSourceBase." }

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force `
    $Stage,(Join-Path $Stage "seeds"), `
    (Join-Path $Stage "src"), `
    (Join-Path $Stage "mods"), `
    (Join-Path $Stage "psxrecomp-cli\libexec"), `
    (Join-Path $Stage "psxrecomp-cli\share"), `
    (Split-Path $OutputPath) | Out-Null

Copy-Item -LiteralPath (Join-Path $Root "release\README-PLAYER.md") -Destination (Join-Path $Stage "README.md")
Copy-Item -LiteralPath (Join-Path $Root "release\SETUP.ps1") -Destination $Stage
Copy-Item -LiteralPath (Join-Path $Root "release\extract_boot_exe.py") -Destination $Stage
foreach ($Name in @("game.toml", "CMakeLists.txt", "settings.toml", "keybinds.ini")) {
    Copy-Item -LiteralPath (Join-Path $Root $Name) -Destination $Stage
}
Copy-Item -LiteralPath (Join-Path $Root "release\BASELINE_POLICY.json") -Destination $Stage
Copy-Item -LiteralPath (Join-Path $Root "seeds\functions.txt") -Destination (Join-Path $Stage "seeds")
Copy-Item -LiteralPath (Join-Path $Root "src\sf2_mods.c") -Destination (Join-Path $Stage "src")
Copy-Item -Path (Join-Path $Root "mods\*") -Destination (Join-Path $Stage "mods") -Recurse
Copy-Item -LiteralPath (Join-Path $Framework "LICENSE") -Destination (Join-Path $Stage "LICENSE-psxrecomp")
Copy-Item -LiteralPath (Join-Path $Framework "THIRD_PARTY_ATTRIBUTION.md") -Destination $Stage

Copy-Item -LiteralPath (Join-Path $Cli "psxrecomp.exe") -Destination (Join-Path $Stage "psxrecomp-cli")
foreach ($Name in @("psxrecomp-game.exe", "psxrecomp-bios.exe", "psxrecomp-toml.exe")) {
    Copy-Item -LiteralPath (Join-Path $Cli "libexec\$Name") -Destination (Join-Path $Stage "psxrecomp-cli\libexec")
}
Copy-Item -LiteralPath (Join-Path $Cli "share\phase2_ghidra_seeds.json") -Destination (Join-Path $Stage "psxrecomp-cli\share")

$SourceProvenance = [ordered]@{
    schema = "sf2-source-provenance-v1"
    selected_source_base = $SelectedSourceBase
    source_commit = $SourceCommit
    source_tree = $SourceTree
    origin = "https://github.com/Alexbeav/syphon-filter-2-recompiled.git"
}
[IO.File]::WriteAllText(
    (Join-Path $Stage "SOURCE_PROVENANCE.json"),
    ($SourceProvenance | ConvertTo-Json -Depth 3) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

$SetupBat = Join-Path $Stage "SETUP.bat"
$SetupBatText = @"
@echo off
cd /d "%~dp0"
echo Syphon Filter 2 Recompiled will acquire any missing build tools.
echo All dependency archives are pinned, downloaded directly, and SHA-256 verified before extraction.
echo WinGet, Git, pip, and Visual Studio are not required. A setup.log file will be written for support; review it before sharing.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SETUP.ps1" -InstallDependencies
if errorlevel 1 (
  echo.
  echo Setup failed. Review the message above.
  pause
  exit /b 1
)
call "%~dp0play.bat"
"@
$SetupBatText = ($SetupBatText -replace "`r?`n", "`r`n")
[IO.File]::WriteAllText($SetupBat, $SetupBatText, [Text.Encoding]::ASCII)

$ManifestFiles = [Collections.Generic.List[object]]::new()
foreach ($File in Get-ChildItem -LiteralPath $Stage -Recurse -File | Sort-Object FullName) {
    $Relative = $File.FullName.Substring($Stage.Length + 1).Replace('\', '/')
    $ManifestFiles.Add([ordered]@{
        path = $Relative
        size = [int64]$File.Length
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
    })
}
$PackageManifest = [ordered]@{
    schema = "sf2-owned-input-package-v1"
    title = "Syphon Filter 2"
    region = "USA"
    source = $SourceProvenance
    retail_payload_included = $false
    generated_game_code_included = $false
    files = $ManifestFiles
}
[IO.File]::WriteAllText(
    (Join-Path $Stage "PACKAGE_MANIFEST.json"),
    ($PackageManifest | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $OutputPath
python (Join-Path $Root "tools\public_repo_audit.py") --archive $OutputPath --sha256
if ($LASTEXITCODE -ne 0) { throw "owned-input kit audit failed" }
Write-Host "Owned-input kit: $OutputPath"
