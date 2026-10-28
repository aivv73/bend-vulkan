#!/usr/bin/env python3
"""Build and check the general examples without the voxel consumer."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from verify import BUILD, run


def main():
    BUILD.mkdir(exist_ok=True)
    for source, name, expected in (
        ('examples/discover.bend', 'discover', 'Loader API version bits:'),
        ('examples/indexed_offscreen.bend', 'indexed-offscreen', 'Indexed RGBA8+D32 every-pixel occlusion'),
        ('examples/offscreen_roundtrip.bend', 'offscreen-roundtrip', 'Optimal RGBA8 image clear'),
        ('examples/buffer_roundtrip.bend', 'buffer-roundtrip', 'Host roundtrip and GPU buffer fill verified'),
    ):
        binary = BUILD / name
        run("bend", source, "-o", str(binary))
        result = run(str(binary), text=True, capture_output=True, timeout=60)
        (BUILD / f"{name}.log").write_text(result.stdout + result.stderr)
        print(result.stdout, end="", flush=True)
        if expected not in result.stdout:
            raise SystemExit(f"{name} omitted its success marker")
        linked = subprocess.run(["ldd", str(binary)], check=True, text=True, capture_output=True).stdout
        if "libX11" in linked or "libxcb" in linked:
            raise SystemExit(f"Headless example gained a display dependency: {name}")
        if name == "discover":
            (BUILD / "discovery.txt").write_text(result.stdout)
    print("General Vulkan examples passed.")


if __name__ == "__main__":
    main()
