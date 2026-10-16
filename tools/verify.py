#!/usr/bin/env python3
"""Check generation and proofs, then build and run the public Vulkan examples."""
import argparse
import os
import pathlib
import re
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
    parser.add_argument("--presentation", action="store_true", help="also require real X11 window acceptance and presentation failure probes")
    parser.add_argument("--isolated-display", action="store_true", help="use a private rootful Xwayland server for presentation checks")
    args = parser.parse_args()
    if args.isolated_display and not args.presentation:
        parser.error("--isolated-display requires --presentation")
    if not (ROOT / "deps/bend-collections/src/math/u64.bend").is_file():
        raise SystemExit("Initialize the pinned dependency: git submodule update --init --recursive")
    voxel = ROOT / "deps/bend-voxel"
    if not (voxel / "voxel.bend").is_file():
        raise SystemExit("Initialize the pinned dependency: git submodule update --init --recursive")
    pin = subprocess.run(["git", "-C", str(voxel), "rev-parse", "HEAD"], check=True,
                         text=True, capture_output=True).stdout.strip()
    if pin != "cdfd92d356229c5de5f4aaddd358f15ec3686dd4":
        raise SystemExit(f"Unexpected bend-voxel revision: {pin}")
    if not shutil.which("bend"):
        raise SystemExit("Bend 2.0.37 is required on PATH")
    version = subprocess.run(["bend", "version"], cwd=ROOT, check=True,
                             text=True, capture_output=True).stdout.strip()
    if version != "bend 2.0.37":
        raise SystemExit(f"The native effect ABI requires bend 2.0.37; found {version}")
    run(sys.executable, "tools/generate.py", "--check")
    run(sys.executable, "tools/build_shaders.py", "--check")
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
    run("bend", "tests/graphics_abi.bend", "-o", str(BUILD / "graphics-abi"))
    run(str(BUILD / "graphics-abi"), timeout=60)
    run("bend", "tests/presentation_abi.bend", "-o", str(BUILD / "presentation-abi"))
    run(str(BUILD / "presentation-abi"), timeout=60)
    discovery_output = ""
    for source, name, expected in (
        ("examples/voxel_offscreen.bend", "voxel-offscreen", "Voxel complete geometry, RGBA8+D32 references"),
        ("examples/discover.bend", "discover", "Loader API version bits:"),
        ("examples/indexed_offscreen.bend", "indexed-offscreen", "Indexed RGBA8+D32 every-pixel occlusion"),
        ("examples/offscreen_roundtrip.bend", "offscreen-roundtrip", "Optimal RGBA8 image clear"),
        ("examples/buffer_roundtrip.bend", "buffer-roundtrip", "Host roundtrip and GPU buffer fill verified"),
        ("tests/viewport.bend", "viewport", "Viewport square rays, wide-field picking and extent rejection passed"),
        ("tests/interactive.bend", "interactive", "Queued edit/reset picking before upload passed"),
        ("tests/semaphores.bend", "semaphores", "Binary semaphore signal-to-wait literal GPU readback passed"),
        ("tests/discovery.bend", "discovery-tests", "Capability discovery and raw limb adapters passed"),
        ("tests/native.bend", "native-tests", "Native Vulkan checks passed"),
        ("tests/transfers.bend", "transfers", "Packed upload and GPU copy passed"),
        ("tests/image_repeated.bend", "image-repeated", "32 distinct color+D32"),
        ("tests/image_formats.bend", "image-formats", "RGBA/BGRA UNORM/SRGB raw channels"),
        ("tests/indexed_graphics.bend", "indexed-graphics", "Every RGBA8/D32 pixel passed"),
        ("tests/graphics_resources.bend", "graphics-resources", "Real shader/layout/pipeline lifecycle"),
        ("tests/rendering.bend", "rendering", "Real color+D32 pass clears"),
        ("tests/offscreen.bend", "offscreen", "Every-pixel clear and padded two-layer"),
        ("tests/images.bend", "images", "Six optimal image formats"),
        ("tests/repeated.bend", "repeated", "32 repeated GPU transfers and 32 private-fence reuses passed"),
    ):
        binary = BUILD / name
        run("bend", source, "-o", str(binary))
        completed = run(str(binary), text=True, capture_output=True, timeout=180 if name == "voxel-offscreen" else 60)
        (BUILD / f"{name}.log").write_text(completed.stdout + completed.stderr)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        if name in {"discover", "voxel-offscreen"}:
            linked = subprocess.run(["ldd", str(binary)], check=True, text=True, capture_output=True).stdout
            if "libX11" in linked or "libxcb" in linked:
                raise SystemExit(f"Headless binary gained a display dependency: {name}\n{linked}")
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
        for name in ("semaphores", "voxel-offscreen", "buffer-roundtrip", "offscreen-roundtrip", "native-tests", "transfers", "repeated", "images", "offscreen", "rendering", "image-repeated", "image-formats", "graphics-resources", "indexed-offscreen", "indexed-graphics"):
            completed = run(str(BUILD / name), env=validation_env, text=True, capture_output=True, timeout=180 if name == "voxel-offscreen" else 60)
            (BUILD / f"{name}-validation.log").write_text(completed.stdout + completed.stderr)
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
    voxel_c = BUILD / "voxel-offscreen.c"
    run("bend", "examples/voxel_offscreen.bend", "-o", str(voxel_c))
    preprocessed = BUILD / "voxel-offscreen-preprocessed.c"
    run("clang", "-std=c11", "-E", "-P", str(voxel_c), "-o", str(preprocessed))
    if re.search(r"\b(?:cuLaunchKernel|cuInit|nvrtcCreateProgram)\s*\(", preprocessed.read_text()):
        raise SystemExit("CPU voxel translation unit retains CUDA dispatch")
    if (BUILD / "voxel-offscreen.gpu").exists():
        raise SystemExit("Unexpected voxel GPU artifact; remove the stale build artifact and rerun")
    if args.sanitize:
        voxel_sanitized = BUILD / "voxel-offscreen-sanitized"
        run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", str(voxel_c), "-lpthread", "-lm", "-ldl", "-o", str(voxel_sanitized))
        completed = run(str(voxel_sanitized), env=env, text=True, capture_output=True, timeout=240)
        (BUILD / "voxel-offscreen-sanitized.log").write_text(completed.stdout + completed.stderr)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
    run(sys.executable, "tools/check_native.py", *(["--sanitize"] if args.sanitize else []))
    if args.presentation:
        presentation_flags = (["--sanitize"] if args.sanitize else []) + (["--isolated-display"] if args.isolated_display else [])
        run(sys.executable, "tools/check_presentation.py", *presentation_flags)
        run(sys.executable, "tools/check_window.py", "--build", "--all", *presentation_flags)
        run(sys.executable, "tools/check_window.py", "--product", *(["--isolated-display"] if args.isolated_display else []))
    print("Generation, proofs, and native Vulkan integration passed.")


if __name__ == "__main__":
    main()
