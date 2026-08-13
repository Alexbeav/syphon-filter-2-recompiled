# Phase 1 standardized baseline

This branch prepares a launcher-ready Syphon Filter 2 baseline from public
source `e08aaff871a5c9b4a7756a6ed6fe99c98c4dbc0f`.

The player supplies the exact USA Disc 1 (SCUS-94451) and Disc 2
(SCUS-94492). Setup verifies each CUE and data-track SHA-256 value before tool
discovery, generation, or compilation. It rejects a missing, ambiguous, or
changed disc.

The faithful default profile uses PCSX-Redux OpenBIOS in LLE mode. BIOS HLE
and fast boot are disabled. The display is native 4:3 at 640x480 with retail
20 Hz world timing. Digital controller input remains available. Supersampling,
antialiasing, widescreen, PGXP, mouse camera, and frame interpolation are off.
Existing optional Mods remain available through the launcher.

`-NoInstallDependencies` is strict offline mode. It accepts only dependencies
that already have the exact pinned receipts and required files. It never
downloads a missing dependency.

The owned-input package contains source-owned configuration and redistributable
tools only. `SOURCE_PROVENANCE.json` binds the selected base, exact product
commit, and source tree. `PACKAGE_MANIFEST.json` binds every package file.
Private setup output records the exact discs, toolchain, BIOS, configuration,
executable, and launcher hashes in `SF2_LOCAL_BUILD_INFO.json`.

This result can be promoted only as `launcher-ready`. It makes no new mission,
campaign, enhancement, full-game, or release-readiness claim.
