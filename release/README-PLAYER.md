# Syphon Filter 2 Recompiled — owned-input player kit

This kit builds the complete two-disc **Syphon Filter 2 (USA)** campaign as a
native Windows x64 program using PSXRecomp, bootstrapped from SCUS-94451. It
contains no game executable, generated game/BIOS code, game assets, Sony BIOS,
saves, or overlay captures.

You must provide the exact legally obtained USA Disc 1 (SCUS-94451) and Disc 2
(SCUS-94492) `.cue` plus `.bin` track pairs. Setup fails closed if either disc
is absent or has the wrong identity. The runtime uses PSXRecomp's bundled
MIT-licensed OpenBIOS backend; a Sony BIOS dump is not required.

The setup script extracts and hash-checks `SCUS_944.51`, regenerates the game
and OpenBIOS backends locally, builds the runtime and the real PSXRecomp
graphical launcher, and writes `play.bat`.

## Prerequisites

- Windows 10/11 x64, an internet connection, and approximately 6 GiB free.

That is all for the normal double-click path. `SETUP.bat` finds compatible
existing tools or downloads isolated, pinned, SHA-256-verified WinLibs and
Python archives directly into the kit. PSXRecomp, the launcher, and SDL are
also acquired as verified source archives. **WinGet, Git, pip, and Visual
Studio are not required.** Nothing is installed system-wide.
The large runtime compile uses at most four parallel jobs by default so it
remains reliable on lower-memory systems. Advanced users can pass
`-BuildJobs N` (1-64) to `SETUP.ps1` to change the limit.

## Easiest setup

Put the extracted kit and both complete disc pairs in the same folder. Setup
selects the CUE names containing `Disc 1` and `Disc 2`, then verifies both
exact CUE and data-track identities. Then double-click:

```text
SETUP.bat
```

The first build downloads pinned dependencies and can take several minutes.
Every archive is verified before extraction; extraction reports a heartbeat
every ten seconds and stops rather than waiting forever. When setup succeeds,
the PSXRecomp launcher opens automatically. Future runs only require
`play.bat`; the launcher lets you choose the disc, video, controller, keyboard,
and memory-card settings.

A complete `setup.log` is written beside `SETUP.bat`. Review it and redact
personal paths before attaching it to a public setup report.

## PowerShell setup

If automatic Disc 1 selection is ambiguous, open PowerShell in the extracted
kit and choose the CUE explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SETUP.ps1 `
  -CuePath "D:\PS1\Syphon Filter 2 (USA) (Disc 1).cue" `
  -Disc2CuePath "D:\PS1\Syphon Filter 2 (USA) (Disc 2).cue"
```

The script recognizes `python` or the Windows `py` launcher and checks standard
installation locations as well as `PATH`. It similarly recognizes MSYS2,
older WinGet WinLibs layouts, and its kit-local verified toolchain. Downloads
are capped at 30 minutes; extraction stops with a useful error after 15
minutes. You can override the compiler with
`-Mingw "D:\Tools\mingw64"`, or use `-NoInstallDependencies` for a strictly
strict offline execution. This mode refuses every missing or unverified
dependency before any download can start. Do not move individual files out of
the extracted kit. Memory cards are stored under `out\release\saves`.

The standardized default is OpenBIOS LLE with BIOS HLE and fast boot disabled,
native 4:3, retail 20 Hz world timing, digital controller availability, and
supersampling, antialiasing, widescreen, PGXP, mouse camera, and interpolation
disabled. Existing optional Mods remain available in the launcher.

## Dependency-only check

You can acquire and verify every public dependency before selecting a disc:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SETUP.ps1 `
  -DependenciesOnly -InstallDependencies
```

This checks or installs the kit-local compiler and Python runtime, then
downloads and verifies the pinned PSXRecomp, launcher, and SDL source trees.
It does not read a disc or generate game code. A successful rerun reuses the
verified trees. A hash mismatch removes the downloaded archive before it can
be extracted.

If a download or extraction cannot finish, setup reports the owning dependency
and timeout in `setup.log`. Check free space and security-software quarantine,
then rerun the same command; completed verified dependencies are not repeated.

## Current state

- Both discs, the connected campaign, and the disc transition have been played
  and verified; public regression reports remain welcome.
- Mouse Look, Widescreen (16:9), and PGXP are independent launcher Mods. All
  three default off; enable only the enhancements you want before Launch.
- The Controls page supports two keyboard/mouse bindings per retail PAD
  control and applies saved edits to the same launch.
- Retail gameplay, scripts, AI, collision, camera ownership, saves, and the
  authentic 20 Hz world update remain game-owned.
- The resident executable is statically recompiled. Uncovered streamed
  overlays use the compatibility interpreter; native overlay promotion is
  deliberately disabled in this alpha and native coverage is incomplete.

True 60 FPS gameplay is not attainable through this project's pure
post-projection recompilation path. Three presentation experiments were
rejected for ghosting, unstable/cracked geometry, or sparse/incoherent replay.
A correct implementation requires at least partial matching decompilation—or
an equivalent semantic camera/object/bone snapshot and render-at-will
interface—like the architecture used by SF-PC-Port. High refresh is therefore
parked, not an active promise for this project.

## License and privacy

PSXRecomp is PolyForm Noncommercial 1.0.0; see `LICENSE-psxrecomp` and
`THIRD_PARTY_ATTRIBUTION.md`. This kit is for noncommercial research and
private play with legally obtained inputs.

Never redistribute the extracted `input/`, `generated/`, `psxrecomp-src/`,
`out/`, `play.bat`, memory cards, `overlay_captures.json`, or any package made
after running setup. Those local outputs may contain retail-derived code or
private paths.

## About this project

These ports are developed by a hobbyist (a DevSecOps engineer, not a game
programmer) with substantial AI assistance. What keeps that honest: every
change is validated before it ships - boot gates, hardware-oracle A/B
comparisons (Beetle/DuckStation), deterministic replay probes, and a shared
findings registry that documents failures as carefully as successes. AI
writes most of the code; the evidence discipline decides what survives.
Bug reports welcome - expect them to be investigated the same way.

tl;dr AI writes the code, but I always test it myself before pushing
