<p align="center">
  <img src="docs/assets/sf2-recompiled-banner.png" alt="Syphon Filter 2 Recompiled" width="640">
</p>

# Syphon Filter 2 Recompiled

An experimental Windows static recompilation of the complete two-disc
**Syphon Filter 2 (USA)** release, bootstrapped from SCUS-94451 and built with
[PSXRecomp](https://github.com/Alexbeav/psxrecomp).

The release runs the original retail game logic as a native x64 program over
a PlayStation hardware runtime. Its launcher offers optional native 16:9,
PGXP-assisted geometry, and direct mouse camera control while keeping retail
gameplay, scripts, collision, saves, AI, and the 20 Hz world update.

This is a **recompilation, not a decompilation**, and `v0.1.2-alpha` is not a
finished PC port. The project does not contain or distribute the game disc, a
Sony BIOS, extracted assets, generated game C, saves, or overlay captures.

## Download and play

The downloadable artifact is an **owned-input setup kit**, not a prebuilt
game. It contains the compiler/runtime tools and this project's verified
recipe, but no executable containing SF2 code.

1. Download `syphon-filter-2-recompiled-kit-windows-x64.zip` from Releases.
2. Put the exact legally obtained USA Disc 1 (SCUS-94451) and Disc 2
   (SCUS-94492) `.cue`/`.bin` pairs beside the extracted kit files. The Phase 1
   baseline fails closed if either disc is absent or has the wrong identity.
3. Double-click `SETUP.bat`. It auto-detects Disc 1, downloads pinned and
   SHA-256-verified WinLibs, Python, PSXRecomp, launcher, and SDL source
   archives directly, builds locally, and opens the graphical launcher.
   **WinGet, Git, pip, and Visual Studio are not required.**
   Runtime compilation uses at most four parallel jobs by default to avoid
   exhausting memory on capture PCs. Advanced users can pass `-BuildJobs N`
   (1-64) to tune that limit.

If automatic selection is ambiguous, use PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SETUP.ps1 `
  -CuePath "D:\PS1\Syphon Filter 2 (USA) (Disc 1).cue" `
  -Disc2CuePath "D:\PS1\Syphon Filter 2 (USA) (Disc 2).cue"
```

Future runs use the generated `play.bat`. The launcher owns disc selection,
video, controls, and memory-card settings.

Setup writes `setup.log` beside itself. If setup fails, review it, redact any
personal paths, and attach it to an issue instead of reconstructing terminal
messages from memory. Existing compatible Python and MinGW installations are
reused when detected; otherwise isolated verified copies are placed inside
the extracted kit.

To acquire and verify every public dependency before adding a disc, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\SETUP.ps1 `
  -DependenciesOnly -InstallDependencies
```

Rerunning setup reuses a dependency only when its receipt and required files
still match. Hash failures remove the untrusted download before extraction.
`-NoInstallDependencies` is a strict offline mode: it refuses every missing or
unverified tool/source dependency before any download can start.

Extraction, hash verification, game/BIOS recompilation, and the native build
all occur locally from your files. Never redistribute the setup output.

## Current status

The standardized Phase 1 profile is promoted only as launcher-ready. It does
not add a new mission, campaign, enhancement, full-game, or release-readiness
claim. The historical v0.1.2 playthrough record below remains a prior control.

| Area | Status |
|---|---|
| Complete game | Both discs, the connected campaign, and the disc transition have been played and verified |
| Retail gameplay and timing | Preserved |
| Native 16:9 mod | Accepted in Mission 1; default off; broader campaign coverage wanted |
| PGXP mod | Accepted in Mission 1; default off; falls back when provenance is incomplete |
| Mouse Look mod | Chase and manual aim accepted; default off; scripted cameras retain ownership |
| Controller and keyboard | Dual keyboard/mouse binds and controllers use the retail PAD path |
| Saves | Local memory cards; full campaign save/load coverage still wanted |
| Disc handling | Disc 1 and Disc 2 gameplay verified |
| High refresh / 60 FPS | Architecturally parked; requires partial decompilation or an equivalent semantic world interface |
| Native code coverage | Resident executable native; uncovered overlays use interpreter fallback |

The alpha runtime deliberately keeps streamed overlays interpreter-owned.
Automatic overlay compilation is disabled because warmed native shards have a
separate promotion/qualification contract and are not part of this release.

The rejected high-refresh experiments produced smooth host presentation
counters but visibly remained one-third-rate and introduced severe rendering
artifacts. They were removed rather than advertised. The pure recomp pipeline
sees flattened GPU packets after retail code has already combined camera,
object, bone, and projection state; it cannot reconstruct a coherent in-between
world from that boundary. True 60 FPS is therefore unattainable within this
project without at least partial matching decompilation—or an equivalent
semantic camera/object/bone snapshot and render-at-will interface. SF-PC-Port
gets smooth presentation from that higher-level semantic architecture.

## Controls

The release includes an SF2 keyboard profile. The launcher's Controls page can
assign two keys or mouse buttons to every retail PAD control, and edits apply
immediately when Launch is pressed:

- Move: `W/Q/S/E`
- Camera: mouse
- Fire / Square: `Left Ctrl`
- Aim / L1: `Left Alt`
- Crouch / Circle: `Space`
- Interact / Cross: `C`
- Triangle: `F`
- Strafe: `A` / `D`
- Pause / Start: `Escape`

Xbox-style controllers remain supported through the normal PSX controller
path. Mouse1--Mouse5 can be mixed with keyboard or controller play.

## What to test

Playthrough reports are especially useful for:

- campaign regressions on either disc, including checkpoints, deaths, and restarts;
- memory-card save/load across clean launches;
- FMVs, letterboxing, fades, scopes, night vision, menus, and HUD placement;
- scenes where wide geometry appears or disappears at screen edges;
- mouse behavior during scripted cameras and manual aim;
- locations that are unusually slow because an overlay is interpreted.

When filing an issue, include the release version, Windows version, GPU,
renderer, mission/checkpoint, exact reproduction steps, and whether the issue
also occurs in 4:3. Never upload your disc, BIOS, save, generated code,
`overlay_captures.json`, or crash dump without first checking that it contains
no retail bytes or private paths.

## Building from source

The release kit is the supported build route. Its setup script pins framework
commit `452cc0c06ec9fb93f28c5848960f7564c76a1ea8`, extracts and verifies
`SCUS_944.51` (SHA-256
`75a360bf7465dfdec85c14f9ba93862aae2531b48d83fd8d82ba8c9fffa13d33`),
regenerates the BIOS and game backends, and builds with MinGW/Ninja.

CI builds and tests only the redistributable compiler/tooling kit. It never
receives retail inputs and cannot produce the game executable. Local `input/`,
`generated/`, `psxrecomp-src/`, `out/`, and `play.bat` outputs are ignored and
must never be committed or shared.

## Development and provenance

Development was AI-assisted and human-directed. Acceptance is based on
machine-checkable executable identity, deterministic routes, bounded runtime
telemetry, repeated clean-process comparisons, and human visual testing.
Generated game C is never hand-edited; fixes belong in source-owned
recompiler/runtime code or verified configuration.

The framework source is PolyForm Noncommercial 1.0.0. This project is for
noncommercial research, preservation, and private play with legally obtained
inputs. Syphon Filter and its assets remain the property of their respective
rights holders. See [LICENSE](LICENSE) and the notices bundled with each
release.
