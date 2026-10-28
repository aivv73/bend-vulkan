#!/usr/bin/env python3
"""Reject reverse dependencies from the Vulkan API and general examples."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def check():
    library = [ROOT / 'Vulkan.bend', ROOT / 'LAWS.bend', ROOT / 'PROOF.bend',
               *(ROOT / 'src').rglob('*.bend')]
    general = [*(ROOT / 'examples').rglob('*.bend'), *(ROOT / 'tests').rglob('*.bend'),
               *(ROOT / 'shaders').rglob('*.bend')]
    for source in library + general:
        for name in re.findall(r'^\s*import ["\']?(\.[^\s"\']+)', source.read_text(), re.M):
            target = (source.parent / name).resolve()
            relative = target.relative_to(ROOT)
            if relative.parts[0] == 'consumers' or relative.parts[:2] == ('deps', 'bend-voxel'):
                raise SystemExit(f'{source.relative_to(ROOT)} imports the voxel consumer: {name}')
            if source in library and relative.parts[0] in ('examples', 'tests', 'shaders'):
                raise SystemExit(f'Library module {source.relative_to(ROOT)} imports a fixture: {name}')
            if not target.is_file():
                raise SystemExit(f'{source.relative_to(ROOT)} has a missing import: {name}')
    print('Vulkan API and general examples have no consumer imports.')


if __name__ == '__main__':
    check()
