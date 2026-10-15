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
    for source, name, expected in (
        ("examples/discover.bend", "discover", "Loader API version bits:"),
        ("examples/buffer_roundtrip.bend", "buffer-roundtrip", "Host roundtrip and GPU buffer fill verified"),
        ("tests/native.bend", "native-tests", "Native Vulkan checks passed"),
    ):
        binary = BUILD / name
        run("bend", source, "-o", str(binary))
        completed = run(str(binary), text=True, capture_output=True, timeout=60)
        print(completed.stdout, end="", flush=True)
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        if expected not in completed.stdout:
            raise SystemExit(f"{name} omitted its success marker")
    if args.sanitize:
        generated = BUILD / "native-tests.c"
        binary = BUILD / "native-tests-sanitized"
        run("bend", "tests/native.bend", "-o", str(generated))
        run("clang", "-std=c11", "-O1", "-g", "-fsanitize=address,undefined",
            "-fno-omit-frame-pointer", str(generated), "-lpthread", "-lm", "-ldl", "-o", str(binary))
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
        # Vulkan drivers may retain process-global allocations. The tests check our registry count.
        run(str(binary), env=env, timeout=60)
    print("Generation, proofs, and native Vulkan integration passed.")


if __name__ == "__main__":
    main()
