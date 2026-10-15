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


def run(*args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true", help="also run native checks under ASan and UBSan")
    args = parser.parse_args()
    if not (ROOT / "deps/bend-collections/src/math/u64.bend").is_file():
        raise SystemExit("Initialize the pinned dependency: git submodule update --init --recursive")
    if not shutil.which("bend"):
        raise SystemExit("Bend 2.0.37 is required on PATH")
    version = subprocess.run(["bend", "version"], cwd=ROOT, check=True,
                             text=True, capture_output=True).stdout.strip()
    if version != "bend 2.0.37":
        raise SystemExit(f"The native effect ABI requires bend 2.0.37; found {version}")
    run(sys.executable, "tools/generate.py", "--check")
    run("bend", "PROOF.bend")
    BUILD.mkdir(exist_ok=True)
    # The interpreted backend must fail explicitly, with a well-formed Result.
    unsupported = subprocess.run(["bend", "examples/discover.bend"], cwd=ROOT,
                                 text=True, capture_output=True, timeout=60)
    output = unsupported.stdout + unsupported.stderr
    if unsupported.returncode == 0 or "Vulkan error 1610612737: Vulkan requires a native build" not in output:
        raise SystemExit("JavaScript backend did not report the expected native-only error:\n" + output)
    rejected = run("bend", "tests/array_rejection.bend", text=True, capture_output=True, timeout=60)
    if "Interpreted array ownership rejection passed" not in rejected.stdout:
        raise SystemExit("Interpreted array ownership probe omitted its success marker")
    run("bend", "tests/image_abi.bend", "-o", str(BUILD / "image-abi"))
    run(str(BUILD / "image-abi"), timeout=60)
    discovery_output = ""
    for source, name, expected in (
        ("examples/discover.bend", "discover", "Loader API version bits:"),
        ("examples/offscreen_roundtrip.bend", "offscreen-roundtrip", "Optimal RGBA8 image clear"),
        ("examples/buffer_roundtrip.bend", "buffer-roundtrip", "Host roundtrip and GPU buffer fill verified"),
        ("tests/discovery.bend", "discovery-tests", "Capability discovery and raw limb adapters passed"),
        ("tests/native.bend", "native-tests", "Native Vulkan checks passed"),
        ("tests/transfers.bend", "transfers", "Packed upload and GPU copy passed"),
        ("tests/offscreen.bend", "offscreen", "Every-pixel clear and padded two-layer"),
        ("tests/images.bend", "images", "Six optimal image formats"),
        ("tests/repeated.bend", "repeated", "32 repeated GPU transfers and 32 private-fence reuses passed"),
    ):
        binary = BUILD / name
        run("bend", source, "-o", str(binary))
        completed = run(str(binary), text=True, capture_output=True, timeout=60)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        if name == "discover":
            discovery_output = completed.stdout
            (BUILD / "discovery.txt").write_text(discovery_output)
        if expected not in completed.stdout:
            raise SystemExit(f"{name} omitted its success marker")
    validation_available = "Layer: VK_LAYER_KHRONOS_validation\n" in discovery_output
    availability = "available" if validation_available else "unavailable"
    print(f"Khronos validation and synchronization validation: {availability}", flush=True)
    validation_report = f"Khronos validation and synchronization validation: {availability}\n"
    if validation_available:
        validation_env = dict(os.environ, VK_INSTANCE_LAYERS="VK_LAYER_KHRONOS_validation",
                              VK_LAYER_ENABLES="VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT")
        for name in ("buffer-roundtrip", "native-tests", "transfers", "repeated"):
            completed = run(str(BUILD / name), env=validation_env, text=True, capture_output=True, timeout=60)
            diagnostics = completed.stdout + completed.stderr
            if "Validation Error" in diagnostics or "SYNC-HAZARD" in diagnostics:
                raise SystemExit(f"Vulkan validation failed for {name}:\n{diagnostics}")
        validation_report += "Real GPU checks passed with validation and synchronization validation enabled.\n"
    (BUILD / "validation.txt").write_text(validation_report)
    if args.sanitize:
        generated = BUILD / "native-tests.c"
        binary = BUILD / "native-tests-sanitized"
        run("bend", "tests/native.bend", "-o", str(generated))
        run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", str(generated), "-lpthread", "-lm", "-ldl", "-o", str(binary))
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
        # Vulkan drivers may retain process-global allocations. The tests check our registry count.
        run(str(binary), env=env, timeout=60)
    run(sys.executable, "tools/check_native.py", *(["--sanitize"] if args.sanitize else []))
    print("Generation, proofs, and native Vulkan integration passed.")


if __name__ == "__main__":
    main()
