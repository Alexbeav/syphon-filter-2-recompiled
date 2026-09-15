# v0.1.3-alpha

Setup-reliability update. Game behavior, the accepted optional Mods, and the
recompiled output are unchanged from `v0.1.1-alpha` and `v0.1.2-alpha`. This
release only changes how `SETUP.bat` handles failure and what it tells you
when it happens.

Two problems made a failed setup impossible to diagnose, and both appeared
together in a single report.

**Install paths containing a space are now rejected before any work starts.**
The bundled MinGW toolchain cannot build from such a path. Setup previously
verified the disc, regenerated the OpenBIOS backend and recompiled the game —
roughly ten minutes — and only then failed at stage 6 with nothing to act on.
It now checks the kit path up front and names the remedy: move the whole
extracted folder somewhere without spaces, such as `C:\SF2Kit`, and run
`SETUP.bat` again. Nothing needs reinstalling.

**Native tool output now reaches `setup.log`.** `Start-Transcript` records
stdout but not stderr, so CMake, Ninja and the recompiler tools reported their
real errors to the console only. A failed build left the log holding the stage
header and `SETUP FAILED: runtime configuration failed` with nothing between
them — while that same message asked you to attach the log. The four native
tool calls now merge stderr into the transcript, and the failure message
carries the tool's exit code.

If setup fails now, `setup.log` contains the reason.

Included: unchanged from `v0.1.2-alpha`.

- statically recompiled resident executable;
- compatibility interpreter for uncovered streamed overlays;
- optional native 16:9 world presentation with authored 4:3 handling;
- optional PGXP geometry with atomic fallback when provenance is incomplete;
- optional direct mouse chase/aim camera with retail camera ownership;
- keyboard and controller input through the retail PAD path;
- 4x supersampling and OpenGL presentation;
- memory-card persistence;
- bundled MIT-licensed OpenBIOS.

Known limitations: unchanged from `v0.1.2-alpha`.

- broader public regression coverage across both discs is still wanted;
- high-refresh interpolation is not included; gameplay uses retail cadence;
- true 60 FPS is parked because the pure recomp boundary lacks semantic
  camera/object/bone state; it requires partial decompilation or an equivalent
  render-at-will interface;
- overlay execution coverage is incomplete and some areas may be slower;
- late-game HUD, FMV, fullscreen effects, and save/load transitions need more
  public playthrough coverage.

The downloadable artifact is an owned-input setup kit. It does not contain a
game executable: the player supplies SCUS-94451 Disc 1 as the build input and
their Disc 2 for the second half of the game, while the kit uses the
MIT-licensed OpenBIOS and extracts, verifies, recompiles, and builds locally.

This release carries no gameplay change over `v0.1.2-alpha` and inherits its
playthrough qualification. The setup changes were verified directly: the
transcript now retains a failing tool's stderr and exit code, which the
previous code path dropped.
