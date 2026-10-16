#!/usr/bin/env python3
"""Run controlled dispatch and allocation probes in an emitted test translation unit."""
import argparse
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def build(sanitize=False):
    source = ROOT / "build/transfers-probes.c"
    binary = source.with_suffix("")
    source.parent.mkdir(exist_ok=True)
    subprocess.run(["bend", "tests/probe_main.bend", "-o", str(source)], cwd=ROOT, check=True)
    emitted = source.read_text()
    probes = (ROOT / "tests/probes.c").read_text().replace(
        "/* LIFECYCLE PROBES */", (ROOT / "tests/lifecycle_probes.c").read_text())
    probes = probes.replace("/* CAPABILITY PROBES */", (ROOT / "tests/capability_probes.c").read_text())
    probes += "\n" + (ROOT / "tests/image_probes.c").read_text()
    probes += "\n" + (ROOT / "tests/image_transfer_probes.c").read_text()
    probes += "\n" + (ROOT / "tests/render_probes.c").read_text()
    probes += "\n" + (ROOT / "tests/graphics_probes.c").read_text()
    probes += "\n" + (ROOT / "tests/semaphore_probes.c").read_text()
    probes += "\n" + (ROOT / "tests/descriptor_probes.c").read_text()
    macros = re.findall(r"^#define (CID_\w+) \d+$", emitted, re.M)

    def cid(match):
        name = match[1].replace(".", "_").upper()
        matches = [m for m in macros if m == "CID_" + name or m.endswith("_VULKAN_" + name)]
        if len(matches) != 1:
            raise ValueError(f"Missing or ambiguous emitted constructor {name}: {matches}")
        return matches[0]

    probes = re.sub(r"CID\(([^)]+)\)", cid, probes)
    split = probes.index("static unsigned bv_test_barrier_calls;")
    allocator, checks = probes[:split], probes[split:]
    anchor = "static BvRow* bv_add("
    if emitted.count(anchor) != 1:
        raise ValueError("Native reference allocator moved")
    begin = emitted.index("// Bend 2.0.37 effect ABI.")
    end = emitted.index("static void __attribute__((constructor)) bv_register(void)", begin)
    native = emitted[begin:end]
    native = native.replace("malloc(", "bv_test_alloc(").replace("calloc(", "bv_test_calloc(").replace("realloc(", "bv_test_realloc(")
    native = re.sub(r"\bfree\(", "bv_test_free(", native)
    native = native.replace(anchor, allocator + "\n" + anchor)
    emitted = emitted[:begin] + native + emitted[end:]
    emitted = emitted.replace("static void __attribute__((constructor)) bv_register(void)", checks + "\nstatic void __attribute__((constructor)) bv_register(void)")
    emitted, registrations = re.subn(r"(io_eff\(CID_\w+, )bv_cmd_copy_buffer(\);)", r"\1bv_test_copy_buffer\2", emitted)
    if registrations != 1:
        raise ValueError("Copy probe registration moved")
    emitted, images = re.subn(r"(io_eff\(CID_\w+, )bv_destroy_image_view(\);)", r"\1test_destroy_image_view\2", emitted)
    if images != 1:
        raise ValueError("Image resource probe registration moved")
    emitted, transfers = re.subn(r"(io_eff\(CID_\w+, )bv_cmd_clear_color_image(\);)", r"\1test_clear_color_image\2", emitted)
    if transfers != 1:
        raise ValueError("Image transfer probe registration moved")
    emitted, rendering = re.subn(r"(io_eff\(CID_\w+, )bv_cmd_begin_render_pass(\);)", r"\1test_begin_render_pass\2", emitted)
    if rendering != 1:
        raise ValueError("Render pass probe registration moved")
    emitted, graphics = re.subn(r"(io_eff\(CID_\w+, )bv_create_graphics_pipeline(\);)", r"\1test_create_graphics_pipeline\2", emitted)
    if graphics != 1:
        raise ValueError("Graphics pipeline probe registration moved")
    emitted, bindings = re.subn(r"(io_eff\(CID_\w+, )bv_cmd_bind_graphics_pipeline(\);)", r"\1test_bind_graphics_pipeline\2", emitted)
    if bindings != 1:
        raise ValueError("Graphics binding probe registration moved")
    emitted, live = re.subn(r"(io_eff\(CID_\w+, )bv_live_objects(\);)", r"\1test_live_objects\2", emitted)
    if live != 1:
        raise ValueError("Registry cleanup probe registration moved")
    emitted, sync = re.subn(r"(io_eff\(CID_\w+, )bv_submit_synced(\);)", r"\1test_submit_synced\2", emitted)
    if sync != 1:
        raise ValueError("Semaphore submission registration moved")
    emitted, descriptors = re.subn(r"(io_eff\(CID_\w+, )bv_create_descriptor_set_layout(\);)", r"\1test_descriptor_layout\2", emitted)
    if descriptors != 1:
        raise ValueError("Descriptor schema registration moved")
    emitted, descriptor_updates = re.subn(r"(io_eff\(CID_\w+, )bv_update_descriptor_set(\);)", r"\1test_descriptor_update\2", emitted)
    emitted, descriptor_roundtrips = re.subn(r"(io_eff\(CID_\w+, )bv_u64_roundtrip(\);)", r"\1test_descriptor_roundtrip\2", emitted)
    if descriptor_updates != 1 or descriptor_roundtrips != 1:
        raise ValueError("Descriptor GPU failure registration moved")
    source.write_text(emitted)
    flags = ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"] if sanitize else []
    subprocess.run(["clang", "-std=c11", "-O1", "-g", *flags, str(source),
                    "-lpthread", "-lm", "-ldl", "-o", str(binary)], cwd=ROOT, check=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0", UBSAN_OPTIONS="halt_on_error=1")
    completed = subprocess.run([str(binary)], cwd=ROOT, env=env, check=False, timeout=60,
                               text=True, capture_output=True)
    print(completed.stdout, end="", flush=True)
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)
    completed.check_returncode()
    for marker in ("Injected metadata/map/flush", "Injected layer/extension dispatch",
                   "Injected submit OOM/uncertainty", "Controlled image query/create/bind/view rollback",
                   "Controlled image command F32",
                   "Controlled pass/framebuffer allocation rollback",
                   "Controlled image graph idle-error retry",
                   "Real disjoint buffer/optimal-image suballocation",
                   "Controlled graphics creation allocation-before-dispatch",
                   "Controlled graphics readiness, signed extremes",
                   "Every RGBA8/D32 pixel passed",
                   "Controlled semaphore allocation rollback",
                   "Binary semaphore signal-to-wait literal GPU readback",
                   "Controlled descriptor metadata sweeps",
                   "Descriptor graph idle-error retry and loss cleanup",
                   "Literal uniform and rendered D32 sampling",
                   "Literal GPU readback after injected sampled and uniform rewrite OOM",
                   "Controlled native probes and real GPU integration passed"):
        if marker not in completed.stdout:
            raise SystemExit(f"Missing executed probe group: {marker}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitize", action="store_true")
    build(parser.parse_args().sanitize)
