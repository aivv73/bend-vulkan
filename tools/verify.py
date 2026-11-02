#!/usr/bin/env python3
"""Check generation and proofs, then build and run the public Vulkan examples."""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BEND_VERSION = "2.0.39"


def run(*args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    try:
        return subprocess.run(args, cwd=ROOT, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        for output, stream in ((error.stdout, sys.stdout), (error.stderr, sys.stderr)):
            if output:
                print(output.decode(errors="replace") if isinstance(output, bytes) else output,
                      end="", file=stream, flush=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true", help="also run native examples under ASan and UBSan")
    args = parser.parse_args()
    if not (ROOT / "deps/bend-collections/src/math/u64.bend").is_file():
        raise SystemExit("Initialize the pinned dependency: git submodule update --init deps/bend-collections")
    if not shutil.which("bend"):
        raise SystemExit(f"Bend {BEND_VERSION} is required on PATH")
    version = subprocess.run(["bend", "version"], cwd=ROOT, check=True,
                             text=True, capture_output=True).stdout.strip()
    if version != f"bend {BEND_VERSION}":
        raise SystemExit(f"The native effect ABI requires bend {BEND_VERSION}; found {version}")
    BUILD.mkdir(exist_ok=True)
    run(sys.executable, "tools/generate.py", "--check")
    run(sys.executable, "tools/check_layers.py")
    run(sys.executable, "tools/build_shaders.py", "--check")
    run("bend", "PROOF.bend")
    run(sys.executable, "examples/verify.py")
    discovery_output = (BUILD / "discovery.txt").read_text()
    validation_available = "Layer: VK_LAYER_KHRONOS_validation\n" in discovery_output
    availability = "available" if validation_available else "unavailable"
    print(f"Khronos validation and synchronization validation: {availability}", flush=True)
    validation_report = f"Khronos validation and synchronization validation: {availability}\n"
    if validation_available:
        validation_env = dict(os.environ, VK_INSTANCE_LAYERS="VK_LAYER_KHRONOS_validation",
                              VK_LAYER_ENABLES="VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT")
        for name in ("buffer-roundtrip", "offscreen-roundtrip", "indexed-offscreen"):
            completed = run(str(BUILD / name), env=validation_env, text=True, capture_output=True, timeout=60)
            (BUILD / f"{name}-validation.log").write_text(completed.stdout + completed.stderr)
            diagnostics = completed.stdout + completed.stderr
            if "Validation Error" in diagnostics or "SYNC-HAZARD" in diagnostics:
                raise SystemExit(f"Vulkan validation failed for {name}:\n{diagnostics}")
        validation_report += "Real GPU checks passed with validation and synchronization validation enabled.\n"
    (BUILD / "validation.txt").write_text(validation_report)
    if args.sanitize:
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
        # Vulkan drivers may retain process-global allocations.
        for name in ("buffer_roundtrip", "offscreen_roundtrip", "indexed_offscreen"):
            generated = BUILD / f"{name}-sanitized.c"
            binary = generated.with_suffix("")
            run("bend", f"examples/{name}.bend", "-o", str(generated))
            run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
                "-fno-omit-frame-pointer", str(generated), "-lpthread", "-lm", "-ldl", "-o", str(binary))
            run(str(binary), env=env, timeout=60)
    print("Generation, proofs, and real Vulkan example validation passed.")


if __name__ == "__main__":
    main()
