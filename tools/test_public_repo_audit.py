from __future__ import annotations

import contextlib
import io
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile
import hashlib
import importlib.util
import json

import public_repo_audit as audit


class ReleaseAuditTests(unittest.TestCase):
    def copy_setup_fixture(self, root: pathlib.Path) -> pathlib.Path:
        source_root = pathlib.Path(__file__).parents[1]
        setup = source_root / "release" / "SETUP.ps1"
        shutil.copy2(setup, root / "SETUP.ps1")
        shutil.copy2(source_root / "release" / "BASELINE_POLICY.json",
                     root / "BASELINE_POLICY.json")
        return root / "SETUP.ps1"

    def test_runtime_build_has_bounded_parallelism(self) -> None:
        setup = (pathlib.Path(__file__).parents[1] / "release" / "SETUP.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("[ValidateRange(1, 64)]", setup)
        self.assertIn("--parallel $BuildJobs", setup)
        self.assertNotIn("--target psx-runtime --parallel\n", setup)

    def test_phase1_policy_is_faithful_and_two_disc(self) -> None:
        root = pathlib.Path(__file__).parents[1]
        policy = json.loads((root / "release" / "BASELINE_POLICY.json").read_text())
        self.assertEqual([disc["serial"] for disc in policy["discs"]],
                         ["SCUS-94451", "SCUS-94492"])
        self.assertFalse(policy["fast_boot"])
        self.assertFalse(policy["bios"]["bios_hle"])
        self.assertEqual(policy["defaults"]["aspect_ratio"], "4:3")
        self.assertFalse(policy["defaults"]["pgxp"])
        self.assertFalse(policy["defaults"]["widescreen"])
        self.assertFalse(policy["defaults"]["mouse_camera"])
        self.assertFalse(policy["defaults"]["frame_interpolation"])

    def test_noinstall_mode_gates_all_dependency_downloads(self) -> None:
        setup = (pathlib.Path(__file__).parents[1] / "release" / "SETUP.ps1").read_text(
            encoding="utf-8"
        )
        self.assertIn("-NoDownload:$NoInstallDependencies", setup)
        self.assertIn("-NoInstallDependencies forbids network acquisition", setup)

    def make_archive(self, extra: dict[str, bytes] | None = None) -> pathlib.Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = pathlib.Path(temp.name) / "release.zip"
        files = {name: b"safe" for name in audit.ALLOWED_KIT_FILES}
        if extra:
            files.update(extra)
        source = {
            "selected_source_base": "e08aaff871a5c9b4a7756a6ed6fe99c98c4dbc0f",
            "source_commit": "0" * 40,
            "source_tree": "1" * 40,
        }
        files["SOURCE_PROVENANCE.json"] = json.dumps(source).encode()
        files["BASELINE_POLICY.json"] = json.dumps({
            "fast_boot": False,
            "bios": {"bios_hle": False},
            "discs": [{"number": 1}, {"number": 2}],
        }).encode()
        manifest_files = []
        for name, data in sorted(files.items()):
            if name == "PACKAGE_MANIFEST.json":
                continue
            manifest_files.append({
                "path": name,
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            })
        files["PACKAGE_MANIFEST.json"] = json.dumps({
            "schema": "sf2-owned-input-package-v1",
            "source": source,
            "files": manifest_files,
        }).encode()
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
            for name, data in files.items():
                zf.writestr(name, data)
        return path

    def run_audit(self, path: pathlib.Path) -> int:
        with contextlib.redirect_stdout(io.StringIO()), \
             contextlib.redirect_stderr(io.StringIO()):
            return audit.audit_archive(path)

    def test_minimal_release_passes(self) -> None:
        self.assertEqual(self.run_audit(self.make_archive()), 0)

    def test_rejects_capture_payload(self) -> None:
        archive = self.make_archive({"overlay_captures.json": b"retail bytes"})
        self.assertEqual(self.run_audit(archive), 1)

    def test_rejects_private_path(self) -> None:
        archive = self.make_archive({"README.md": b"I:/Projects/private"})
        self.assertEqual(self.run_audit(archive), 1)

    def test_rejects_prebuilt_game_executable(self) -> None:
        archive = self.make_archive({
            "SyphonFilter2Recompiled.exe": b"MZ...retail-derived game",
        })
        self.assertEqual(self.run_audit(archive), 1)

    def test_rejects_zip_traversal(self) -> None:
        archive = self.make_archive({"../escape.txt": b"bad"})
        self.assertEqual(self.run_audit(archive), 1)

    def test_rejects_lf_only_batch_file(self) -> None:
        archive = self.make_archive({"SETUP.bat": b"@echo off\necho bad\n"})
        self.assertEqual(self.run_audit(archive), 1)

    def test_rejects_non_ascii_batch_file(self) -> None:
        archive = self.make_archive({"SETUP.bat": "@echo off\r\necho Γ\r\n".encode("utf-8")})
        self.assertEqual(self.run_audit(archive), 1)

    def test_standard_library_disc_extractor_reads_raw_iso9660(self) -> None:
        extractor_path = pathlib.Path(__file__).parents[1] / "release" / "extract_boot_exe.py"
        spec = importlib.util.spec_from_file_location("sf2_extract_boot_exe", extractor_path)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        extractor = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(extractor)

        def record(name: bytes, lba: int, size: int, flags: int = 0) -> bytes:
            length = 33 + len(name) + (1 if len(name) % 2 == 0 else 0)
            data = bytearray(length)
            data[0] = length
            data[2:6] = lba.to_bytes(4, "little")
            data[6:10] = lba.to_bytes(4, "big")
            data[10:14] = size.to_bytes(4, "little")
            data[14:18] = size.to_bytes(4, "big")
            data[25] = flags
            data[28:30] = (1).to_bytes(2, "little")
            data[30:32] = (1).to_bytes(2, "big")
            data[32] = len(name)
            data[33:33 + len(name)] = name
            return bytes(data)

        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            cue = root / "Disc 1.cue"
            bin_path = root / "Disc 1.bin"
            payload = bytes((index % 251 for index in range(3000)))
            sectors = [bytearray(2352) for _ in range(23)]
            pvd = bytearray(2048)
            pvd[:7] = b"\x01CD001\x01"
            root_record = record(b"\x00", 20, 2048, flags=2)
            pvd[156:156 + len(root_record)] = root_record
            sectors[16][24:24 + 2048] = pvd
            directory = bytearray(2048)
            entries = root_record + record(b"SCUS_944.51;1", 21, len(payload))
            directory[:len(entries)] = entries
            sectors[20][24:24 + 2048] = directory
            sectors[21][24:24 + 2048] = payload[:2048]
            sectors[22][24:24 + len(payload[2048:])] = payload[2048:]
            bin_path.write_bytes(b"".join(sectors))
            cue.write_text('FILE "Disc 1.bin" BINARY\n', encoding="ascii")
            self.assertEqual(extractor.extract_iso_file(cue, "SCUS_944.51;1"), payload)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell is unavailable")
    def test_setup_auto_detects_disc1_beside_disc2(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            disc1 = root / "Syphon Filter 2 (USA) (Disc 1).cue"
            disc2 = root / "Syphon Filter 2 (USA) (Disc 2).cue"
            disc1.write_text("FILE disc1.bin BINARY\n", encoding="ascii")
            disc2.write_text("FILE disc2.bin BINARY\n", encoding="ascii")
            result = subprocess.run(
                ["pwsh", "-NoProfile", "-File", str(root / "SETUP.ps1"),
                 "-ResolveCueOnly"],
                check=True, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            # Windows runners can expose the temporary directory through its
            # 8.3 alias while PowerShell reports the corresponding long path.
            # The selected filename is the behavior this regression protects.
            self.assertIn(disc1.name, result.stdout)
            self.assertNotIn(disc2.name, result.stdout)

    @unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"),
                         "Windows PowerShell is unavailable")
    def test_setup_preflight_accepts_py_launcher_without_python_on_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            fake_bin = root / "toolchain" / "bin"
            fake_bin.mkdir(parents=True)
            for name in ("git", "cmake", "gcc", "g++", "ninja", "py"):
                body = "@echo off\r\nexit /b 0\r\n"
                if name == "py":
                    body = "@echo off\r\nif not \"%PYTHONUTF8%\"==\"1\" exit /b 9\r\nexit /b 0\r\n"
                (fake_bin / f"{name}.cmd").write_text(body, encoding="ascii")
            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + os.environ["SystemRoot"] + "\\System32"
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            result = subprocess.run(
                [shutil.which("pwsh"), "-NoProfile", "-File", str(root / "SETUP.ps1"),
                 "-PreflightOnly", "-NoInstallDependencies"],
                check=True, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, env=env,
            )
            self.assertIn("Python:", result.stdout)
            self.assertIn("py.cmd -3", result.stdout)
            self.assertIn("Visual Studio is not required", result.stdout)

    @unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"),
                         "Windows PowerShell is unavailable")
    def test_setup_preflight_names_missing_python(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            fake_bin = root / "toolchain" / "bin"
            fake_bin.mkdir(parents=True)
            for name in ("git", "cmake", "gcc", "g++", "ninja"):
                (fake_bin / f"{name}.cmd").write_text(
                    "@echo off\r\nexit /b 0\r\n", encoding="ascii"
                )
            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + os.environ["SystemRoot"] + "\\System32"
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            result = subprocess.run(
                [shutil.which("pwsh"), "-NoProfile", "-File", str(root / "SETUP.ps1"),
                 "-PreflightOnly", "-NoInstallDependencies"],
                check=False, text=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Missing: Python 3.10+", result.stdout)
            self.assertIn("Run SETUP.bat for automatic installation", result.stdout)

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell"),
                         "Windows PowerShell 5.1 is unavailable")
    def test_setup_installs_verified_winlibs_without_winget(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            fake_bin = root / "existing-tools"
            fake_bin.mkdir()
            for name in ("git", "cmake", "py"):
                (fake_bin / f"{name}.cmd").write_text(
                    "@echo off\r\nexit /b 0\r\n", encoding="ascii"
                )

            archive = root / "fixture-winlibs.zip"
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
                for name in ("gcc.exe", "g++.exe", "ninja.exe", "cmake.exe"):
                    zf.writestr(f"mingw64/bin/{name}", b"fixture")
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()

            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + os.environ["SystemRoot"] + "\\System32"
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            env["SF2_SETUP_TEST_MODE"] = "1"
            env["SF2_SETUP_TEST_WINLIBS_ARCHIVE"] = str(archive)
            env["SF2_SETUP_TEST_WINLIBS_SHA256"] = digest
            result = subprocess.run(
                [shutil.which("powershell"), "-NoProfile", "-ExecutionPolicy", "Bypass",
                 "-File", str(root / "SETUP.ps1"),
                 "-PreflightOnly", "-InstallDependencies"],
                check=False, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("WinGet is not used", result.stdout)
            self.assertIn("Verified WinLibs", result.stdout)
            self.assertIn("is ready inside this kit", result.stdout)
            self.assertTrue((root / "toolchain" / "winlibs-16.1.0-14.0.0-r4" /
                             "mingw64" / "bin" / "gcc.exe").is_file())

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell"),
                         "Windows PowerShell 5.1 is unavailable")
    def test_setup_rejects_unverified_winlibs_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            fake_bin = root / "existing-tools"
            fake_bin.mkdir()
            for name in ("git", "cmake", "py"):
                (fake_bin / f"{name}.cmd").write_text(
                    "@echo off\r\nexit /b 0\r\n", encoding="ascii"
                )
            archive = root / "untrusted.zip"
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("mingw64/bin/gcc.exe", b"untrusted")

            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + os.environ["SystemRoot"] + "\\System32"
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            env["SF2_SETUP_TEST_MODE"] = "1"
            env["SF2_SETUP_TEST_WINLIBS_ARCHIVE"] = str(archive)
            env["SF2_SETUP_TEST_WINLIBS_SHA256"] = "0" * 64
            result = subprocess.run(
                [shutil.which("powershell"), "-NoProfile", "-ExecutionPolicy", "Bypass",
                 "-File", str(root / "SETUP.ps1"),
                 "-PreflightOnly", "-InstallDependencies"],
                check=False, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("archive hash mismatch", result.stdout)
            self.assertIn("untrusted download was removed", result.stdout)
            self.assertFalse((root / "toolchain" / "winlibs-16.1.0-14.0.0-r4").exists())

    @unittest.skipUnless(os.name == "nt" and shutil.which("powershell"),
                         "Windows PowerShell 5.1 is unavailable")
    def test_setup_acquires_verified_source_closure_without_git(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            fake_bin = root / "existing-tools"
            fake_bin.mkdir()
            for name in ("cmake", "gcc", "g++", "ninja", "py"):
                (fake_bin / f"{name}.cmd").write_text(
                    "@echo off\r\nexit /b 0\r\n", encoding="ascii"
                )

            fixtures = {
                "FRAMEWORK": (
                    "psxrecomp-452cc0c06ec9fb93f28c5848960f7564c76a1ea8",
                    ("runtime/runtime.cmake", "bios/OpenBIOS.toml", "LICENSE"),
                ),
                "RECOMP_UI": (
                    "recomp-ui-514c9e29f6d043867cea2fe91ca3cca24c69477e",
                    ("recomp_ui.cmake", "src/recomp_launcher.h", "README.md"),
                ),
                "SDL3": (
                    "SDL3-3.4.10",
                    ("CMakeLists.txt", "include/SDL3/SDL.h", "LICENSE.txt"),
                ),
            }
            env = os.environ.copy()
            env["PATH"] = str(fake_bin) + os.pathsep + os.environ["SystemRoot"] + "\\System32"
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            env["SF2_SETUP_TEST_MODE"] = "1"
            for key, (prefix, names) in fixtures.items():
                archive = root / f"{key.lower()}.zip"
                with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
                    for name in names:
                        zf.writestr(f"{prefix}/{name}", b"fixture")
                env[f"SF2_SETUP_TEST_{key}_ARCHIVE"] = str(archive)
                env[f"SF2_SETUP_TEST_{key}_SHA256"] = hashlib.sha256(archive.read_bytes()).hexdigest()

            result = subprocess.run(
                [shutil.which("powershell"), "-NoProfile", "-ExecutionPolicy", "Bypass",
                 "-File", str(root / "SETUP.ps1"), "-DependenciesOnly",
                 "-InstallDependencies"],
                check=False, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("Pinned dependency closure is ready", result.stdout)
            self.assertNotIn("git clone", result.stdout.lower())
            self.assertTrue((root / "psxrecomp-src" / ".sf2-artifact-sha256").is_file())
            self.assertTrue((root / "recomp-ui" / ".sf2-artifact-sha256").is_file())
            self.assertTrue((root / "toolchain" / "SDL3-3.4.10" /
                             ".sf2-artifact-sha256").is_file())

    @unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"),
                         "Windows PowerShell is unavailable")
    def test_setup_verifies_both_exact_disc_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            self.copy_setup_fixture(root)
            disc1_bin = root / "Disc 1.bin"
            disc2_bin = root / "Disc 2.bin"
            disc1_bin.write_bytes(b"disc-one-fixture")
            disc2_bin.write_bytes(b"disc-two-fixture")
            disc1 = root / "Syphon Filter 2 (USA) (Disc 1).cue"
            disc2 = root / "Syphon Filter 2 (USA) (Disc 2).cue"
            disc1.write_bytes(b'FILE "Disc 1.bin" BINARY\r\n')
            disc2.write_bytes(b'FILE "Disc 2.bin" BINARY\r\n')
            env = os.environ.copy()
            env["SF2_SETUP_TEST_MODE"] = "1"
            env["SF2_SETUP_TEST_DISC1_CUE_SHA256"] = hashlib.sha256(disc1.read_bytes()).hexdigest()
            env["SF2_SETUP_TEST_DISC1_BIN_SHA256"] = hashlib.sha256(disc1_bin.read_bytes()).hexdigest()
            env["SF2_SETUP_TEST_DISC2_CUE_SHA256"] = hashlib.sha256(disc2.read_bytes()).hexdigest()
            env["SF2_SETUP_TEST_DISC2_BIN_SHA256"] = hashlib.sha256(disc2_bin.read_bytes()).hexdigest()
            result = subprocess.run(
                [shutil.which("pwsh"), "-NoProfile", "-File", str(root / "SETUP.ps1"),
                 "-CuePath", str(disc1), "-Disc2CuePath", str(disc2),
                 "-VerifyDiscSetOnly"],
                check=False, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env,
            )
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn("Exact two-disc input policy passed", result.stdout)

    @unittest.skipUnless(os.name == "nt" and shutil.which("pwsh"),
                         "Windows PowerShell is unavailable")
    def test_setup_rejects_non_ascii_launcher_path_before_tool_discovery(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / "Γιώργος"
            root.mkdir()
            self.copy_setup_fixture(root)
            cue = root / "Syphon Filter 2 (USA) (Disc 1).cue"
            cue.write_text("FILE disc1.bin BINARY\n", encoding="ascii")
            disc2 = root / "Syphon Filter 2 (USA) (Disc 2).cue"
            disc2.write_text("FILE disc2.bin BINARY\n", encoding="ascii")
            env = os.environ.copy()
            env["SF2_SETUP_DISABLE_STANDARD_DISCOVERY"] = "1"
            result = subprocess.run(
                [shutil.which("pwsh"), "-NoProfile", "-File", str(root / "SETUP.ps1"),
                 "-CuePath", str(cue), "-Disc2CuePath", str(disc2),
                 "-NoInstallDependencies"],
                check=False, text=True, encoding="utf-8", errors="replace",
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, env=env,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ASCII-only path", result.stdout)
            self.assertNotIn("== 0/7 prepare build tools ==", result.stdout)


if __name__ == "__main__":
    unittest.main()
