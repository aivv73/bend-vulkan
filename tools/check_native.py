#!/usr/bin/env python3
"""Run controlled dispatch and allocation probes in an emitted test translation unit."""
import argparse
import os
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]


def build(sanitize=False):
    source = ROOT / "build/transfers-probes.c"
    binary = source.with_suffix("")
    subprocess.run(["bend", "tests/transfers.bend", "-o", str(source)], cwd=ROOT, check=True)
    emitted = source.read_text()
    probes = (ROOT / "tests/probes.c").read_text()
    macros = re.findall(r"^#define (CID_\w+) \d+$", emitted, re.M)

    def cid(match):
        name = match[1].replace(".", "_").upper()
        matches = [m for m in macros if m == "CID_" + name or m.endswith("_VULKAN_" + name)]
        if len(matches) != 1:
            raise ValueError(f"Missing or ambiguous emitted constructor {name}: {matches}")
        return matches[0]

    probes = re.sub(r"CID\(([^)]+)\)", cid, probes)
    split = probes.index("static unsigned bv_test_copy_calls;")
    allocator, checks = probes[:split], probes[split:]
    anchor = "static int bv_prepare_refs("
    if emitted.count(anchor) != 1:
        raise ValueError("Native reference allocator moved")
    emitted = emitted.replace(anchor, allocator + "\n" + anchor)
    emitted = emitted.replace("BvUse* use=malloc(sizeof(*use));", "BvUse* use=bv_test_alloc(sizeof(*use));")
    emitted = emitted.replace("static void __attribute__((constructor)) bv_register(void)", checks + "\nstatic void __attribute__((constructor)) bv_register(void)")
    emitted = re.sub(r"(io_eff\(CID_\w+, )bv_cmd_copy_buffer(\);)", r"\1bv_test_copy_buffer\2", emitted)
    source.write_text(emitted)
    flags = ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"] if sanitize else []
    subprocess.run(["clang", "-std=c11", "-O1", "-g", *flags, str(source),
                    "-lpthread", "-lm", "-ldl", "-o", str(binary)], cwd=ROOT, check=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
    subprocess.run([str(binary)], cwd=ROOT, env=env, check=True, timeout=60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true")
    build(parser.parse_args().sanitize)
