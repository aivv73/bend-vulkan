#!/usr/bin/env python3
"""Exercise only this example's X11 window; requires python-xlib and Pillow."""
import os
from pathlib import Path
import subprocess
import sys
import time

from Xlib import X, XK, display, protocol
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from verify import BUILD, run


def wait_for(action, process, description):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'Window exited during {description}: {process.returncode}')
        result = action()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError(f'Timed out: {description}')


def find_window(dpy, pid):
    atom = dpy.intern_atom('_NET_WM_PID')
    pending = [dpy.screen().root]
    while pending:
        node = pending.pop()
        prop = node.get_full_property(atom, X.AnyPropertyType)
        if prop is not None and list(prop.value) == [pid]:
            return node
        pending.extend(node.query_tree().children)


def capture(window):
    geometry = window.get_geometry()
    raw = window.get_image(0, 0, geometry.width, geometry.height, X.ZPixmap, 0xffffffff)
    return Image.frombytes('RGB', (geometry.width, geometry.height), raw.data, 'raw', 'BGRX')


def key(dpy, window, name):
    code = dpy.keysym_to_keycode(XK.string_to_keysym(name))
    for kind, mask in ((protocol.event.KeyPress, X.KeyPressMask), (protocol.event.KeyRelease, X.KeyReleaseMask)):
        window.send_event(kind(time=X.CurrentTime, root=dpy.screen().root, window=window,
                              child=X.NONE, root_x=0, root_y=0, event_x=0, event_y=0,
                              state=0, detail=code, same_screen=1), event_mask=mask)
    dpy.sync()


def close(dpy, window):
    window.send_event(protocol.event.ClientMessage(window=window,
        client_type=dpy.intern_atom('WM_PROTOCOLS'),
        data=(32, [dpy.intern_atom('WM_DELETE_WINDOW'), X.CurrentTime, 0, 0, 0])))
    dpy.sync()


def exercise(dpy, binary, suffix, suspended_close):
    env = dict(os.environ)
    layer_dirs = [Path('/usr/share/vulkan/explicit_layer.d'), Path('/etc/vulkan/explicit_layer.d')]
    available = any('VK_LAYER_KHRONOS_validation' in path.read_text()
                    for directory in layer_dirs for path in directory.glob('*.json'))
    if available:
        env.update(VK_INSTANCE_LAYERS='VK_LAYER_KHRONOS_validation', VK_LAYER_VALIDATE_SYNC='1')
    print(f'Khronos and synchronization validation: {"enabled" if available else "unavailable"}', flush=True)
    log_path = BUILD / f'indexed-window-{suffix}.log'
    with log_path.open('w') as log:
        process = subprocess.Popen([str(binary)], cwd=ROOT, env=env, stdout=log, stderr=log)
        try:
            window = wait_for(lambda: find_window(dpy, process.pid), process, 'window creation')
            wait_for(lambda: window.get_attributes().map_state == X.IsViewable, process, 'mapping')
            first = wait_for(lambda: rendered(window), process, 'indexed cube and floor')
            first.save(BUILD / f'indexed-window-{suffix}.png')
            key(dpy, window, 'd')
            wait_for(lambda: ImageChops.difference(first, capture(window)).getbbox(), process, 'camera movement')
            key(dpy, window, 'r')
            wait_for(lambda: ImageChops.difference(first, capture(window)).getbbox() is None, process, 'camera reset')
            for width, height in ((800, 450), (360, 640), (720, 480), (640, 480)):
                window.configure(width=width, height=height)
                dpy.sync()
                wait_for(lambda: resized(window, width, height), process, 'resize and rendering')
                time.sleep(0.1)
            window.unmap()
            dpy.sync()
            time.sleep(0.2)
            if suspended_close:
                close(dpy, window)
            else:
                window.map()
                dpy.sync()
                wait_for(lambda: window.get_attributes().map_state == X.IsViewable and rendered(window), process, 'restore')
                key(dpy, window, 'Escape')
            process.wait(timeout=15)
            if process.returncode:
                raise RuntimeError(f'Window failed: {log_path.read_text()}')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
    output = log_path.read_text()
    if 'Indexed window closed; live Vulkan objects: 0' not in output:
        raise RuntimeError(f'Missing clean shutdown: {output}')
    if any(marker in output for marker in ('Validation Error', 'SYNC-HAZARD', 'VUID-')):
        raise RuntimeError(f'Validation diagnostics: {output}')


def rendered(window):
    image = capture(window)
    colors = image.getcolors(image.width * image.height)
    # Flat-shaded cube faces must survive the floor, which is submitted last.
    substantial = [rgb for count, rgb in colors if count > 100]
    warm = any(r > 150 and r > g * 1.15 and r > b * 1.5 for r, g, b in substantial)
    cool = any(g > 100 and g > r * 1.5 for r, g, b in substantial)
    r, g, b = image.getpixel((image.width // 2, image.height // 2))
    center_is_cube = (r > 150 and r > b * 1.5) or (g > 100 and g > r * 1.5)
    return image if warm and cool and center_is_cube and len(substantial) >= 5 else None


def resized(window, width, height):
    size = window.get_geometry()
    return size.width == width and size.height == height and rendered(window)


def main():
    BUILD.mkdir(exist_ok=True)
    binary = BUILD / 'indexed-window'
    run('bend', 'examples/indexed_window.bend', '-o', str(binary))
    dpy = display.Display()
    try:
        exercise(dpy, binary, 'escape', False)
        exercise(dpy, binary, 'close', True)
    finally:
        dpy.close()
    print('Indexed window camera, repeated resize, unmap/restore, Escape and suspended close passed; zero live objects.')


if __name__ == '__main__':
    main()
