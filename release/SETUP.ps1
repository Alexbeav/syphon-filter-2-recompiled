param(
    [string]$CuePath,
    [string]$Disc2CuePath,
    [string]$Mingw,
    [switch]$ResolveCueOnly,
    [switch]$VerifyDiscSetOnly,
    [switch]$InstallDependencies,
    [switch]$NoInstallDependencies,
    [switch]$PreflightOnly,
    [switch]$DependenciesOnly,
    [ValidateRange(1, 64)]
    [int]$BuildJobs = [Math]::Min(4, [Math]::Max(1, [Environment]::ProcessorCount))
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"
$Kit = $PSScriptRoot
$Framework = Join-Path $Kit "psxrecomp-src"
$FrameworkRef = "452cc0c06ec9fb93f28c5848960f7564c76a1ea8"
$FrameworkArchiveName = "psxrecomp-$FrameworkRef.zip"
$FrameworkUrl = "https://github.com/Alexbeav/psxrecomp/archive/$FrameworkRef.zip"
$FrameworkSha256 = "87ce5cff803f6e5bcf0a5efb3720bf98e4fbb718c5d55b903a2425de0cd8d1c2"
$RecompUi = Join-Path $Kit "recomp-ui"
$RecompUiRef = "514c9e29f6d043867cea2fe91ca3cca24c69477e"
$RecompUiArchiveName = "recomp-ui-$RecompUiRef.zip"
$RecompUiUrl = "https://github.com/Alexbeav/recomp-ui/archive/$RecompUiRef.zip"
$RecompUiSha256 = "1bb283d579c3553028fec28202258aae24a43b429bfb8aca6ad854702ba3826a"
$InputDir = Join-Path $Kit "input"
$GeneratedDir = Join-Path $Kit "generated"
$BuildDir = Join-Path $Kit "out\release"
$ToolchainDir = Join-Path $Kit "toolchain"
$WinLibsVersion = "16.1.0-14.0.0-r4"
$WinLibsArchiveName = "winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r4.zip"
$WinLibsUrl = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r4/$WinLibsArchiveName"
$WinLibsSha256 = "c406a22f8cac82559a3a1d96b62ff603f666499fb5ff4784e87b4eb6fa37dede"
$WinLibsRoot = Join-Path $ToolchainDir "winlibs-$WinLibsVersion"
$PythonVersion = "3.13.14"
$PythonArchiveName = "python-$PythonVersion-embed-amd64.zip"
$PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/$PythonArchiveName"
$PythonSha256 = "90b4e5b9898b72d744650524bff92377c367f44bd5fbd09e3148656c080ad907"
$PythonRoot = Join-Path $ToolchainDir "python-$PythonVersion"
$SdlVersion = "3.4.10"
$SdlArchiveName = "SDL3-$SdlVersion.tar.gz"
$SdlUrl = "https://github.com/libsdl-org/SDL/releases/download/release-$SdlVersion/$SdlArchiveName"
$SdlSha256 = "12b34280415ec8418c864408b93d008a20a6530687ee613d60bfbd20411f2785"
$SdlRoot = Join-Path $ToolchainDir "SDL3-$SdlVersion"
$SetupLog = Join-Path $Kit "setup.log"
$TranscriptStarted = $false
$PolicyPath = Join-Path $Kit "BASELINE_POLICY.json"
$SourceProvenancePath = Join-Path $Kit "SOURCE_PROVENANCE.json"

if (-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)) {
    throw "Phase 1 baseline policy is missing: $PolicyPath"
}
$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json

function Refresh-ProcessPath {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$MachinePath;$UserPath"
}

function Get-Sha256 {
    param([string]$Path)

    $Stream = [IO.File]::OpenRead($Path)
    try {
        $Hasher = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($Hasher.ComputeHash($Stream)) -replace "-", "").ToLowerInvariant()
        } finally {
            $Hasher.Dispose()
        }
    } finally {
        $Stream.Dispose()
    }
}

function Get-ExpectedDiscHash {
    param([string]$Key, [string]$Default)

    if ($env:SF2_SETUP_TEST_MODE -eq "1") {
        $Override = [Environment]::GetEnvironmentVariable("SF2_SETUP_TEST_${Key}_SHA256")
        if (-not [string]::IsNullOrWhiteSpace($Override)) {
            return $Override.ToLowerInvariant()
        }
    }
    return $Default.ToLowerInvariant()
}

function Resolve-CueDataTrack {
    param([string]$Cue)

    $Text = Get-Content -LiteralPath $Cue -Raw
    $Matches = [regex]::Matches($Text, '(?im)^\s*FILE\s+"([^"]+)"\s+BINARY\s*$')
    if ($Matches.Count -ne 1) {
        throw "Expected one quoted BINARY FILE entry in CUE: $Cue"
    }
    $Track = Join-Path (Split-Path $Cue -Parent) $Matches[0].Groups[1].Value
    if (-not (Test-Path -LiteralPath $Track -PathType Leaf)) {
        throw "CUE data track not found: $Track"
    }
    return (Resolve-Path -LiteralPath $Track).Path
}

function Assert-DiscIdentity {
    param([int]$Number, [string]$Cue)

    $Disc = @($Policy.discs | Where-Object { [int]$_.number -eq $Number })
    if ($Disc.Count -ne 1) { throw "Baseline policy does not define Disc $Number exactly once." }
    $CueHash = Get-Sha256 $Cue
    $Track = Resolve-CueDataTrack $Cue
    $TrackHash = Get-Sha256 $Track
    $ExpectedCue = Get-ExpectedDiscHash "DISC${Number}_CUE" ([string]$Disc[0].cue_sha256)
    $ExpectedTrack = Get-ExpectedDiscHash "DISC${Number}_BIN" ([string]$Disc[0].bin_sha256)
    if ($CueHash -ne $ExpectedCue) {
        throw "Disc $Number CUE identity mismatch. Expected $ExpectedCue, got $CueHash."
    }
    if ($TrackHash -ne $ExpectedTrack) {
        throw "Disc $Number data-track identity mismatch. Expected $ExpectedTrack, got $TrackHash."
    }
    Write-Host "Verified Disc $Number $($Disc[0].serial): CUE $CueHash; data track $TrackHash" -ForegroundColor Green
    return [pscustomobject]@{
        Number = $Number
        Serial = [string]$Disc[0].serial
        Cue = $Cue
        CueSha256 = $CueHash
        Track = $Track
        TrackSha256 = $TrackHash
    }
}

function Assert-PublicDependencyTree {
    param([string]$Root, [string]$Label)

    $Forbidden = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
        $_.Name -match '(?i)\.(mcd|mcr|psxstate|cue|chd|iso|img|ccd|sub|bmp|wav|mp4|mkv)$' -or
        $_.Name -match '(?i)^SCUS[_-]?944\.(51|92)$' -or
        $_.FullName -match '(?i)[\\/](captures|traces|saves)[\\/]'
    })
    if ($Forbidden.Count) {
        throw "$Label dependency tree contains private/runtime material: $($Forbidden[0].FullName)"
    }
}

function Get-DirectoryIdentity {
    param([string]$Root)

    $Rows = [Collections.Generic.List[string]]::new()
    $Bytes = [int64]0
    $Prefix = $Root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($File in Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName) {
        $Relative = $File.FullName.Substring($Prefix.Length).Replace('\', '/')
        $Hash = Get-Sha256 $File.FullName
        $Rows.Add("$Relative`t$($File.Length)`t$Hash")
        $Bytes += $File.Length
    }
    $Payload = [Text.Encoding]::UTF8.GetBytes(($Rows -join "`n"))
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $Digest = ([BitConverter]::ToString($Hasher.ComputeHash($Payload)) -replace '-', '').ToLowerInvariant()
    } finally { $Hasher.Dispose() }
    return [ordered]@{ files = $Rows.Count; bytes = $Bytes; manifest_sha256 = $Digest }
}

function Find-Application {
    param([string]$Name, [string[]]$Candidates = @())

    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($Command) { return $Command.Source }
    if ($env:SF2_SETUP_DISABLE_STANDARD_DISCOVERY -eq "1") { return $null }

    foreach ($Pattern in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($Pattern)) { continue }
        $Match = Get-ChildItem -Path $Pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($Match) { return $Match.FullName }
    }
    return $null
}

function Test-PythonCandidate {
    param([string]$File, [string[]]$Prefix = @())

    if ([string]::IsNullOrWhiteSpace($File)) { return $null }
    try {
        & $File @Prefix -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ File = $File; Prefix = @($Prefix) }
        }
    } catch {
        return $null
    }
    return $null
}

function Find-Python {
    $PinnedPython = Join-Path $PythonRoot "python.exe"
    $Result = Test-PythonCandidate $PinnedPython
    if ($Result) { return $Result }

    $PythonCommand = Get-Command python -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($PythonCommand -and $PythonCommand.Source -notmatch '(?i)\\WindowsApps\\python(?:3)?\.exe$') {
        $Result = Test-PythonCandidate $PythonCommand.Source
        if ($Result) { return $Result }
    }

    $PyCommand = Get-Command py -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($PyCommand) {
        $Result = Test-PythonCandidate $PyCommand.Source @("-3")
        if ($Result) { return $Result }
    }

    if ($env:SF2_SETUP_DISABLE_STANDARD_DISCOVERY -ne "1") {
        $Candidates = @(
            "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
            "$env:ProgramFiles\Python*\python.exe",
            "${env:ProgramFiles(x86)}\Python*\python.exe"
        )
        foreach ($Pattern in $Candidates) {
            if ([string]::IsNullOrWhiteSpace($Pattern)) { continue }
            foreach ($Candidate in @(Get-ChildItem -Path $Pattern -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending)) {
                $Result = Test-PythonCandidate $Candidate.FullName
                if ($Result) { return $Result }
            }
        }
    }
    return $null
}

function Find-MingwToolchain {
    param([string]$RequestedRoot)

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $Root = [IO.Path]::GetFullPath($RequestedRoot)
        $Gcc = Join-Path $Root "bin\gcc.exe"
        $Gxx = Join-Path $Root "bin\g++.exe"
        $Ninja = Join-Path $Root "bin\ninja.exe"
        $CMake = Join-Path $Root "bin\cmake.exe"
        if ((Test-Path -LiteralPath $Gcc) -and (Test-Path -LiteralPath $Gxx) -and
            (Test-Path -LiteralPath $Ninja) -and (Test-Path -LiteralPath $CMake)) {
            return [pscustomobject]@{ Root = $Root; Gcc = $Gcc; Gxx = $Gxx; Ninja = $Ninja; CMake = $CMake }
        }
        return $null
    }

    $PathGcc = Get-Command gcc -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $PathGxx = Get-Command g++ -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $PathNinja = Get-Command ninja -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $PathCMake = Get-Command cmake -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($PathGcc -and $PathGxx -and $PathNinja -and
        (Split-Path $PathGcc.Source -Parent) -eq (Split-Path $PathGxx.Source -Parent) -and
        (Split-Path $PathGcc.Source -Parent) -eq (Split-Path $PathNinja.Source -Parent) -and
        $PathCMake) {
        return [pscustomobject]@{
            Root = Split-Path (Split-Path $PathGcc.Source -Parent) -Parent
            Gcc = $PathGcc.Source
            Gxx = $PathGxx.Source
            Ninja = $PathNinja.Source
            CMake = $PathCMake.Source
        }
    }

    $Roots = @((Join-Path $WinLibsRoot "mingw64"))
    if ($env:SF2_SETUP_DISABLE_STANDARD_DISCOVERY -ne "1") {
        $Roots += @("C:\msys64\mingw64", "C:\mingw64")
        if ($env:LOCALAPPDATA) {
            $Roots += @(Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.*" -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Join-Path $_.FullName "mingw64" })
        }
    }
    foreach ($Root in $Roots) {
        $Gcc = Join-Path $Root "bin\gcc.exe"
        $Gxx = Join-Path $Root "bin\g++.exe"
        $Ninja = Join-Path $Root "bin\ninja.exe"
        $CMake = Join-Path $Root "bin\cmake.exe"
        if ((Test-Path -LiteralPath $Gcc) -and (Test-Path -LiteralPath $Gxx) -and
            (Test-Path -LiteralPath $Ninja) -and (Test-Path -LiteralPath $CMake)) {
            return [pscustomobject]@{ Root = $Root; Gcc = $Gcc; Gxx = $Gxx; Ninja = $Ninja; CMake = $CMake }
        }
    }
    return $null
}

function Resolve-SetupTools {
    param([string]$RequestedMingw)
    return [pscustomobject]@{
        Python = Find-Python
        Mingw = Find-MingwToolchain $RequestedMingw
    }
}

function Get-MissingToolNames {
    param($Tools)
    $Missing = @()
    if (-not $Tools.Python) { $Missing += "Python 3.10+" }
    if (-not $Tools.Mingw) { $Missing += "MinGW-w64 GCC + CMake + Ninja" }
    return $Missing
}

function Install-MissingTools {
    param($Tools)
    if (-not $Tools.Mingw) { Install-PinnedWinLibs }
    if (-not $Tools.Python) { Install-PinnedPython }
}

function Install-VerifiedArtifact {
    param(
        [string]$Key,
        [string]$Label,
        [string]$Url,
        [string]$ExpectedSha256,
        [string]$ArchiveName,
        [string]$Destination,
        [string]$ArchiveRoot,
        [string[]]$RequiredFiles,
        [switch]$NoDownload
    )

    $Receipt = Join-Path $Destination ".sf2-artifact-sha256"
    $Complete = Test-Path -LiteralPath $Receipt -PathType Leaf
    if ($Complete) {
        $Complete = (Get-Content -LiteralPath $Receipt -Raw).Trim() -eq $ExpectedSha256
        foreach ($Required in $RequiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $Destination $Required) -PathType Leaf)) {
                $Complete = $false
            }
        }
    }
    if ($Complete) {
        Write-Host "$Label already verified inside this kit." -ForegroundColor Green
        return
    }

    if ($NoDownload) {
        throw "$Label is missing or failed its receipt check. -NoInstallDependencies forbids network acquisition; pre-populate the exact verified dependency closure."
    }

    $Downloads = Join-Path $ToolchainDir "downloads"
    $Archive = Join-Path $Downloads $ArchiveName
    $PartialArchive = "$Archive.part"
    $ExtractingRoot = "$Destination.extracting-$PID"

    New-Item -ItemType Directory -Force $Downloads | Out-Null
    if (Test-Path -LiteralPath $PartialArchive) {
        Remove-Item -LiteralPath $PartialArchive -Force
    }

    $TestArchive = [Environment]::GetEnvironmentVariable("SF2_SETUP_TEST_${Key}_ARCHIVE")
    $TestSha256 = [Environment]::GetEnvironmentVariable("SF2_SETUP_TEST_${Key}_SHA256")
    Write-Host "Downloading pinned $Label directly (WinGet is not used)..." -ForegroundColor Cyan
    if ($env:SF2_SETUP_TEST_MODE -eq "1" -and $TestArchive) {
        Copy-Item -LiteralPath $TestArchive -Destination $PartialArchive
        $ExpectedSha256 = $TestSha256
    } else {
        $Curl = Find-Application "curl.exe" @("$env:SystemRoot\System32\curl.exe")
        if (-not $Curl) {
            throw "Windows curl.exe is unavailable. See README.md for the manual dependency path."
        }
        & $Curl --fail --location --retry 3 --connect-timeout 30 --max-time 1800 `
            --output $PartialArchive $Url
        if ($LASTEXITCODE -ne 0) {
            throw "$Label download failed (curl exit $LASTEXITCODE). Check the connection and rerun SETUP.bat."
        }
    }

    $ActualSha256 = Get-Sha256 $PartialArchive
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256) -or
        $ActualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $PartialArchive -Force
        throw "$Label archive hash mismatch; the untrusted download was removed. Expected $ExpectedSha256, got $ActualSha256."
    }
    Move-Item -LiteralPath $PartialArchive -Destination $Archive -Force
    Write-Host "Verified $Label archive SHA-256: $ActualSha256" -ForegroundColor Green

    if (Test-Path -LiteralPath $ExtractingRoot) {
        Remove-Item -LiteralPath $ExtractingRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force $ExtractingRoot | Out-Null
    $Tar = Find-Application "tar.exe" @("$env:SystemRoot\System32\tar.exe")
    if (-not $Tar) {
        throw "Windows tar.exe is unavailable. See README.md for the manual dependency path."
    }

    Write-Host "Extracting verified $Label (progress is reported every 10 seconds)..." -ForegroundColor Cyan
    $StartInfo = New-Object Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $Tar
    $StartInfo.Arguments = "-xf `"$Archive`" -C `"$ExtractingRoot`""
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $Process = New-Object Diagnostics.Process
    $Process.StartInfo = $StartInfo
    if (-not $Process.Start()) { throw "Could not start Windows tar.exe for $Label extraction." }
    $ElapsedSeconds = 0
    while (-not $Process.WaitForExit(10000)) {
        $ElapsedSeconds += 10
        Write-Host "  Still extracting $Label... $ElapsedSeconds seconds elapsed"
        if ($ElapsedSeconds -ge 900) {
            Stop-Process -Id $Process.Id -Force
            throw "$Label extraction exceeded 15 minutes and was stopped. Free disk space and antivirus scanning are common causes; see setup.log."
        }
    }
    $Process.WaitForExit()
    $TarExitCode = $Process.ExitCode
    $Process.Dispose()
    if ($TarExitCode -ne 0) {
        throw "$Label extraction failed (tar exit $TarExitCode). See setup.log."
    }

    $ExtractedArtifact = if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        $ExtractingRoot
    } else {
        Join-Path $ExtractingRoot $ArchiveRoot
    }
    foreach ($Required in $RequiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $ExtractedArtifact $Required) -PathType Leaf)) {
            throw "Verified $Label archive did not contain $Required."
        }
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    if ([string]::IsNullOrWhiteSpace($ArchiveRoot)) {
        Move-Item -LiteralPath $ExtractingRoot -Destination $Destination
    } else {
        Move-Item -LiteralPath $ExtractedArtifact -Destination $Destination
        Remove-Item -LiteralPath $ExtractingRoot -Recurse -Force
    }
    [IO.File]::WriteAllText((Join-Path $Destination ".sf2-artifact-sha256"), $ExpectedSha256, [Text.Encoding]::ASCII)
    Remove-Item -LiteralPath $Archive -Force
    Write-Host "$Label is ready inside this kit: $Destination" -ForegroundColor Green
}

function Install-PinnedWinLibs {
    Install-VerifiedArtifact "WINLIBS" "WinLibs $WinLibsVersion" $WinLibsUrl $WinLibsSha256 `
        $WinLibsArchiveName $WinLibsRoot "" `
        @("mingw64\bin\gcc.exe", "mingw64\bin\g++.exe", "mingw64\bin\ninja.exe", "mingw64\bin\cmake.exe")
}

function Install-PinnedPython {
    Install-VerifiedArtifact "PYTHON" "Python $PythonVersion embeddable runtime" $PythonUrl $PythonSha256 `
        $PythonArchiveName $PythonRoot "" @("python.exe", "python313.dll", "python313.zip")
}

function Install-PinnedSources {
    param([switch]$NoDownload)

    Install-VerifiedArtifact "FRAMEWORK" "PSXRecomp source $FrameworkRef" $FrameworkUrl $FrameworkSha256 `
        $FrameworkArchiveName $Framework "psxrecomp-$FrameworkRef" `
        @("runtime\runtime.cmake", "bios\OpenBIOS.toml", "LICENSE") -NoDownload:$NoDownload
    Install-VerifiedArtifact "RECOMP_UI" "PSXRecomp launcher source $RecompUiRef" $RecompUiUrl $RecompUiSha256 `
        $RecompUiArchiveName $RecompUi "recomp-ui-$RecompUiRef" `
        @("recomp_ui.cmake", "src\recomp_launcher.h", "README.md") -NoDownload:$NoDownload
    Install-VerifiedArtifact "SDL3" "SDL $SdlVersion source" $SdlUrl $SdlSha256 `
        $SdlArchiveName $SdlRoot "SDL3-$SdlVersion" `
        @("CMakeLists.txt", "include\SDL3\SDL.h", "LICENSE.txt") -NoDownload:$NoDownload
}

function Invoke-Python {
    param($Python, [string[]]$Arguments)
    $AllArguments = @($Python.Prefix) + $Arguments
    & $Python.File @AllArguments
}

function Assert-AsciiLauncherPath {
    param([string]$Path, [string]$Label)

    if ($Path -match '[^\x00-\x7F]') {
        throw "$Label contains characters that play.bat cannot safely represent: $Path. Move the extracted kit and both disc files to an ASCII-only path such as C:\Games\SF2, then run SETUP.bat again."
    }
}

function Show-ToolSummary {
    param($Tools)
    $PythonLabel = $Tools.Python.File
    if ($Tools.Python.Prefix.Count) { $PythonLabel += " " + ($Tools.Python.Prefix -join " ") }
    Write-Host "Build tools ready:" -ForegroundColor Green
    Write-Host "  Python:  $PythonLabel"
    Write-Host "  CMake:   $($Tools.Mingw.CMake)"
    Write-Host "  GCC:     $($Tools.Mingw.Gcc)"
    Write-Host "  Ninja:   $($Tools.Mingw.Ninja)"
    Write-Host "  Visual Studio is not required."
}

if (-not $ResolveCueOnly) {
    try {
        Start-Transcript -LiteralPath $SetupLog -Append | Out-Null
        $TranscriptStarted = $true
        Write-Host "Syphon Filter 2 Recompiled setup" -ForegroundColor Cyan
        Write-Host "A complete log is written to: $SetupLog"
    } catch {
        $TranscriptStarted = $false
    }
}

trap {
    Write-Host ""
    Write-Host "SETUP FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Review setup.log, redact personal paths, and attach it if the message above is not enough."
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    exit 1
}

if ($PreflightOnly -or $DependenciesOnly) {
    $Tools = Resolve-SetupTools $Mingw
    $Missing = @(Get-MissingToolNames $Tools)
    if ($Missing.Count -and -not $NoInstallDependencies) {
        if ($InstallDependencies) {
            Install-MissingTools $Tools
        } else {
            $Reply = Read-Host "Missing $($Missing -join ', '). Download pinned verified tools into this kit? [Y/n]"
            if ([string]::IsNullOrWhiteSpace($Reply) -or $Reply -match '^(?i)y(?:es)?$') {
                Install-MissingTools $Tools
            }
        }
        $Tools = Resolve-SetupTools $Mingw
        $Missing = @(Get-MissingToolNames $Tools)
    }
    if ($Missing.Count) {
        throw "Missing: $($Missing -join ', '). Run SETUP.bat for automatic installation, or install the listed tools and rerun."
    }
    Show-ToolSummary $Tools
    if ($DependenciesOnly) {
        Install-PinnedSources -NoDownload:$NoInstallDependencies
        Write-Host "Pinned dependency closure is ready." -ForegroundColor Green
    }
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($CuePath)) {
    $AllCues = @(Get-ChildItem -LiteralPath $Kit -File -Filter "*.cue")
    $Disc1Cues = @($AllCues | Where-Object { $_.BaseName -match '(?i)disc\s*1' })
    if ($Disc1Cues.Count -eq 1) {
        $CuePath = $Disc1Cues[0].FullName
    } elseif ($AllCues.Count -eq 1) {
        $CuePath = $AllCues[0].FullName
    } else {
        $Found = if ($AllCues.Count) {
            ($AllCues.FullName | ForEach-Object { "  $_" }) -join [Environment]::NewLine
        } else {
            "  (none)"
        }
        throw "Could not uniquely find Disc 1 beside SETUP.ps1. Found:`n$Found`nRun SETUP.ps1 -CuePath <Disc 1.cue> to choose it explicitly."
    }
    Write-Host "Auto-detected Disc 1: $CuePath"
}
if (-not (Test-Path -LiteralPath $CuePath -PathType Leaf)) {
    throw "Disc 1 CUE not found: $CuePath"
}
$CuePath = (Resolve-Path -LiteralPath $CuePath).Path
if ($ResolveCueOnly) {
    Write-Output $CuePath
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Disc2CuePath)) {
    $Disc2Cues = @(Get-ChildItem -LiteralPath $Kit -File -Filter "*.cue" |
        Where-Object { $_.BaseName -match '(?i)disc\s*2' })
    if ($Disc2Cues.Count -ne 1) {
        $Found = if ($Disc2Cues.Count) {
            ($Disc2Cues.FullName | ForEach-Object { "  $_" }) -join [Environment]::NewLine
        } else { "  (none)" }
        throw "Could not uniquely find Disc 2 beside SETUP.ps1. Found:`n$Found`nRun SETUP.ps1 -CuePath <Disc 1.cue> -Disc2CuePath <Disc 2.cue>."
    }
    $Disc2CuePath = $Disc2Cues[0].FullName
    Write-Host "Auto-detected Disc 2: $Disc2CuePath"
}
if (-not (Test-Path -LiteralPath $Disc2CuePath -PathType Leaf)) {
    throw "Disc 2 CUE not found: $Disc2CuePath"
}
$Disc2CuePath = (Resolve-Path -LiteralPath $Disc2CuePath).Path
if ($CuePath -eq $Disc2CuePath) { throw "Disc 1 and Disc 2 must be different CUE files." }

# play.bat is deliberately ASCII+CRLF for cmd.exe compatibility. Reject paths
# that would otherwise be silently replaced with '?' before doing a long build.
Assert-AsciiLauncherPath $Kit "The extracted kit path"
Assert-AsciiLauncherPath $CuePath "The Disc 1 CUE path"
Assert-AsciiLauncherPath $Disc2CuePath "The Disc 2 CUE path"

$Disc1Identity = Assert-DiscIdentity 1 $CuePath
$Disc2Identity = Assert-DiscIdentity 2 $Disc2CuePath
if ($VerifyDiscSetOnly) {
    Write-Host "Exact two-disc input policy passed." -ForegroundColor Green
    if ($TranscriptStarted) { Stop-Transcript | Out-Null }
    exit 0
}

Write-Host "== 0/7 prepare build tools =="
$Tools = Resolve-SetupTools $Mingw
$Missing = @(Get-MissingToolNames $Tools)
if ($Missing.Count) {
    if ($NoInstallDependencies) {
        throw "Missing: $($Missing -join ', '). Run SETUP.bat for automatic installation, or install the listed tools and rerun."
    }
    if ($InstallDependencies) {
        Install-MissingTools $Tools
    } else {
        $Reply = Read-Host "Missing $($Missing -join ', '). Download pinned verified tools into this kit? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($Reply) -or $Reply -match '^(?i)y(?:es)?$') {
            Install-MissingTools $Tools
        } else {
            throw "Setup cannot continue without $($Missing -join ', '). Visual Studio is not required."
        }
    }
    $Tools = Resolve-SetupTools $Mingw
    $Missing = @(Get-MissingToolNames $Tools)
    if ($Missing.Count) {
        throw "Installation completed but setup still cannot locate: $($Missing -join ', '). See setup.log."
    }
}
Show-ToolSummary $Tools

$BuildPython = $Tools.Python.File
if ($Tools.Python.Prefix.Count) {
    $BuildPython = (& $Tools.Python.File @($Tools.Python.Prefix) -c "import sys; print(sys.executable)").Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $BuildPython -PathType Leaf)) {
        throw "Could not resolve the native Python executable behind $($Tools.Python.File)."
    }
}

$env:PATH = "$(Split-Path $Tools.Mingw.Gcc -Parent);$(Split-Path $Tools.Python.File -Parent);$env:PATH"

Write-Host "== 1/7 acquire pinned, verified PSXRecomp source =="
Install-PinnedSources -NoDownload:$NoInstallDependencies

Write-Host "== 2/7 verify offline launcher and SDL source closure =="
Write-Host "All build sources are hash-verified and ready inside this kit." -ForegroundColor Green
Assert-PublicDependencyTree $Framework "PSXRecomp"
Assert-PublicDependencyTree $RecompUi "recomp-ui"
Assert-PublicDependencyTree $SdlRoot "SDL"

if (-not (Test-Path -LiteralPath $SourceProvenancePath -PathType Leaf)) {
    throw "Source provenance is missing: $SourceProvenancePath"
}
$SourceProvenance = Get-Content -LiteralPath $SourceProvenancePath -Raw | ConvertFrom-Json
if ([string]$SourceProvenance.selected_source_base -ne [string]$Policy.selected_source_base -or
    [string]$SourceProvenance.source_commit -notmatch '^[0-9a-f]{40}$' -or
    [string]$SourceProvenance.source_tree -notmatch '^[0-9a-f]{40}$') {
    throw "Source provenance does not bind the selected Phase 1 base and exact product source."
}
$ConfigText = Get-Content -LiteralPath (Join-Path $Kit "game.toml") -Raw
$SettingsText = Get-Content -LiteralPath (Join-Path $Kit "settings.toml") -Raw
if ($ConfigText -notmatch '(?m)^bios_hle\s*=\s*false\s*$' -or
    $ConfigText -notmatch '(?m)^fast_boot\s*=\s*false\s*$' -or
    $ConfigText -notmatch '(?m)^aspect_ratio\s*=\s*"4:3"\s*$' -or
    $ConfigText -notmatch '(?m)^pgxp\s*=\s*false\s*$' -or
    $ConfigText -notmatch '(?ms)^\[controller\.mouse_camera\]\s*\r?\n\s*enabled\s*=\s*false\s*$' -or
    $ConfigText -notmatch '(?ms)^\[widescreen\]\s*\r?\n\s*offer\s*=\s*false\s*$') {
    throw "game.toml violates the faithful Phase 1 BIOS, fast-boot, 4:3, or default-off enhancement policy."
}
if ($SettingsText -notmatch '(?m)^supersampling\s*=\s*1\s*$' -or
    $SettingsText -notmatch '(?m)^antialiasing\s*=\s*false\s*$' -or
    $SettingsText -notmatch '(?m)^aspect_ratio\s*=\s*"4:3"\s*$' -or
    $SettingsText -notmatch '(?m)^frame_interpolation\s*=\s*false\s*$') {
    throw "settings.toml violates the faithful Phase 1 presentation policy."
}
$OpenBios = Join-Path $Framework "bios\openbios.bin"
$OpenBiosNotice = Join-Path $Framework "bios\OpenBIOS.LICENSE"
if (-not (Test-Path -LiteralPath $OpenBios -PathType Leaf) -or
    -not (Test-Path -LiteralPath $OpenBiosNotice -PathType Leaf)) {
    throw "The pinned OpenBIOS image or license notice is missing."
}
$OpenBiosSha256 = Get-Sha256 $OpenBios
if ($OpenBiosSha256 -ne [string]$Policy.bios.sha256) {
    throw "OpenBIOS identity mismatch. Expected $($Policy.bios.sha256), got $OpenBiosSha256."
}

Write-Host "== 3/7 extract and verify SCUS_944.51 from your Disc 1 =="
New-Item -ItemType Directory -Force $InputDir | Out-Null
Invoke-Python $Tools.Python @((Join-Path $Kit "extract_boot_exe.py"), $CuePath, $InputDir)
if ($LASTEXITCODE -gt 1) { throw "boot executable extraction failed" }
if ($LASTEXITCODE -eq 1) {
    throw "unsupported SCUS_944.51 revision; see the hash warning above"
}

Write-Host "== 4/7 regenerate the MIT-licensed OpenBIOS backend =="
New-Item -ItemType Directory -Force (Join-Path $Framework "generated") | Out-Null
$BiosTool = Join-Path $Kit "psxrecomp-cli\libexec\psxrecomp-bios.exe"
Push-Location $Framework
try {
    & $BiosTool --config bios/OpenBIOS.toml
    if ($LASTEXITCODE -ne 0) { throw "BIOS recompilation failed" }
} finally {
    Pop-Location
}

Write-Host "== 5/7 recompile the resident game executable =="
$GameTool = Join-Path $Kit "psxrecomp-cli\libexec\psxrecomp-game.exe"
Push-Location $Kit
try {
    & $GameTool --config game.toml
    if ($LASTEXITCODE -ne 0) { throw "game recompilation failed" }
} finally {
    Pop-Location
}

Write-Host "== 6/7 build the native runtime and PSXRecomp launcher =="
Write-Host "Using $BuildJobs parallel build jobs (override with -BuildJobs 1..64)."
& $Tools.Mingw.CMake -S $Kit -B $BuildDir -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_C_COMPILER=$($Tools.Mingw.Gcc -replace '\\','/')" `
    "-DCMAKE_CXX_COMPILER=$($Tools.Mingw.Gxx -replace '\\','/')" `
    "-DCMAKE_MAKE_PROGRAM=$($Tools.Mingw.Ninja -replace '\\','/')" `
    "-DPSXRECOMP_ROOT=$($Framework -replace '\\','/')" `
    "-DRECOMP_UI_ROOT=$($RecompUi -replace '\\','/')" `
    "-DFETCHCONTENT_SOURCE_DIR_SDL3=$($SdlRoot -replace '\\','/')" `
    "-DPSX_PYTHON=$($BuildPython -replace '\\','/')" `
    -DPSX_DEBUG_TOOLS=ON `
    -DPSX_RECOMP_UI=ON
if ($LASTEXITCODE -ne 0) { throw "runtime configuration failed" }
& $Tools.Mingw.CMake --build $BuildDir --target psx-runtime --parallel $BuildJobs
if ($LASTEXITCODE -ne 0) { throw "runtime build failed" }

Write-Host "== 7/7 stage private inputs and write launcher =="
$BuildSaves = Join-Path $BuildDir "saves"
New-Item -ItemType Directory -Force $BuildSaves | Out-Null
Copy-Item -LiteralPath (Join-Path $Kit "settings.toml") -Destination $BuildDir -Force
Copy-Item -LiteralPath (Join-Path $Kit "keybinds.ini") -Destination $BuildDir -Force

$Exe = Join-Path $BuildDir "SyphonFilter2Recompiled.exe"
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
    throw "built runtime not found: $Exe"
}
$Cue = $CuePath
$Config = Join-Path $Kit "game.toml"
$Launcher = Join-Path $Kit "play.bat"
$BuildBios = Join-Path $BuildDir "bios\openbios.bin"
if (-not (Test-Path -LiteralPath $BuildBios -PathType Leaf) -or
    (Get-Sha256 $BuildBios) -ne $OpenBiosSha256) {
    throw "The built launcher directory does not contain the exact accepted OpenBIOS image."
}
$LauncherText = @"
@echo off
set "PSX_OVERLAY_AUTOCOMPILE_OFF=1"
set "PSX_NATIVE_RANK_LIMIT=0"
cd /d "$BuildDir"
start "Syphon Filter 2 Recompiled" "$Exe" --launcher --renderer opengl --game "$Config" --disc "$Cue" --bios "$BuildBios" --memcard-dir "$BuildSaves"
"@
$LauncherText = ($LauncherText -replace "`r?`n", "`r`n")
[IO.File]::WriteAllText($Launcher, $LauncherText, [Text.Encoding]::ASCII)

$BuildInfo = [ordered]@{
    schema = "sf2-local-build-v1"
    title = "Syphon Filter 2"
    region = "USA"
    selected_source_base = [string]$SourceProvenance.selected_source_base
    source_commit = [string]$SourceProvenance.source_commit
    source_tree = [string]$SourceProvenance.source_tree
    source_provenance_sha256 = (Get-Sha256 $SourceProvenancePath)
    discs = @(
        [ordered]@{ number = 1; serial = $Disc1Identity.Serial; cue_sha256 = $Disc1Identity.CueSha256; bin_sha256 = $Disc1Identity.TrackSha256 },
        [ordered]@{ number = 2; serial = $Disc2Identity.Serial; cue_sha256 = $Disc2Identity.CueSha256; bin_sha256 = $Disc2Identity.TrackSha256 }
    )
    retail_executable_sha256 = [string]$Policy.discs[0].boot_executable_sha256
    framework_archive_sha256 = $FrameworkSha256
    recomp_ui_archive_sha256 = $RecompUiSha256
    sdl_archive_sha256 = $SdlSha256
    dependency_trees = [ordered]@{
        psxrecomp = (Get-DirectoryIdentity $Framework)
        recomp_ui = (Get-DirectoryIdentity $RecompUi)
        sdl = (Get-DirectoryIdentity $SdlRoot)
    }
    openbios_sha256 = $OpenBiosSha256
    openbios_notice_present = $true
    bios_hle_default = $false
    fast_boot_default = $false
    aspect_ratio_default = "4:3"
    retail_world_update_hz = 20
    controller_mode = "digital"
    mouse_camera_default = $false
    optional_enhancements_default = $false
    toolchain = [ordered]@{
        python_sha256 = (Get-Sha256 $Tools.Python.File)
        cmake_sha256 = (Get-Sha256 $Tools.Mingw.CMake)
        ninja_sha256 = (Get-Sha256 $Tools.Mingw.Ninja)
        c_compiler_sha256 = (Get-Sha256 $Tools.Mingw.Gcc)
        cxx_compiler_sha256 = (Get-Sha256 $Tools.Mingw.Gxx)
    }
    game_config_sha256 = (Get-Sha256 $Config)
    settings_sha256 = (Get-Sha256 (Join-Path $BuildDir "settings.toml"))
    keybinds_sha256 = (Get-Sha256 (Join-Path $BuildDir "keybinds.ini"))
    executable_sha256 = (Get-Sha256 $Exe)
    launcher_sha256 = (Get-Sha256 $Launcher)
    owned_paths_recorded = $false
    retail_bytes_redistributable = $false
    generated_game_code_redistributable = $false
    completed_at_utc = [DateTime]::UtcNow.ToString("o")
}
[IO.File]::WriteAllText(
    (Join-Path $Kit "SF2_LOCAL_BUILD_INFO.json"),
    ($BuildInfo | ConvertTo-Json -Depth 6) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Setup complete. Run play.bat to open the PSXRecomp launcher." -ForegroundColor Green
Write-Host "Private generated files remain only inside this extracted kit."
if ($TranscriptStarted) { Stop-Transcript | Out-Null }
