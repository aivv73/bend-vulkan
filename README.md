# bend-vulkan

A native Vulkan wrapper for Bend, inspired by [ash](https://github.com/ash-rs/ash).
It provides explicit GPU memory, command recording, synchronization, and indexed graphics on 64-bit Linux.

## What works

The wrapper implements a Vulkan 1.0 subset with optional X11 presentation:

- Device and capability discovery, buffers, memory allocation, packed uploads, and GPU transfers.
- Optimal-tiled 2D color and depth images, staging readback, render passes, and indexed depth-tested draws.
- Uniform-buffer and combined-image-sampler descriptors, push constants, and timestamp queries.
- Explicit barriers, fences, semaphores, command reuse, and independent submissions.
- Checked handles, scoped cleanup, and deferred retirement of buffers referenced by recorded commands.

The [roadmap](docs/roadmap.md) tracks implemented work and planned API and platform expansion.

## Build your first example

Install these prerequisites:

- 64-bit Linux with glibc 2.34 or newer.
- **Bend 2.0.39**, the version required by the native effect ABI.
- Clang, Python 3, Vulkan development headers, and `libvulkan.so.1`.
- A Vulkan driver with a graphics queue. A software driver such as Lavapipe is sufficient for the buffer example.

Confirm that `bend version` prints `bend 2.0.39`. From the repository root, initialize the library dependency and build:

```sh
git submodule update --init deps/bend-collections
mkdir -p build
bend examples/buffer_roundtrip.bend -o build/buffer-roundtrip
./build/buffer-roundtrip
```

Expected output:

```text
Host roundtrip and GPU buffer fill verified
```

The example checks a host-memory roundtrip, fills a buffer on the GPU, and compares the readback bytes.
Headless examples need no display or X11 library. CUDA is not required.

Use `-o` to build a native executable. Running `bend examples/buffer_roundtrip.bend` directly selects the JavaScript backend, where Vulkan effects return a native-build-required error.

## Explore the headless examples

Build any example with the same `bend <source> -o <binary>` command:

| Source | What it demonstrates |
| --- | --- |
| [discover.bend](examples/discover.bend) | Enumerate devices, layers, extensions, memory heaps, formats, and limits |
| [buffer_roundtrip.bend](examples/buffer_roundtrip.bend) | Host memory access and GPU buffer fill |
| [offscreen_roundtrip.bend](examples/offscreen_roundtrip.bend) | Clear an RGBA8 image and verify every pixel through staging readback |
| [indexed_offscreen.bend](examples/indexed_offscreen.bend) | Verify indexed draws and depth occlusion with UINT16 and UINT32 indices |

Check these examples independently from the repository root:

```sh
bend examples/verify.bend -o build/verify-examples
./build/verify-examples
```

## Run the independent window example

[indexed_window.bend](examples/indexed_window.bend) renders a colored indexed cube above a floor with a perspective orbit camera and depth testing. It depends only on this library and bend-collections.

In addition to the headless prerequisites, install X11 development headers and `libX11.so.6`, and run in an X11 session (or XWayland) with `DISPLAY` set. The Vulkan driver must support `VK_EXT_swapchain_maintenance1`; see the [presentation profile](docs/presentation.md#api-profile).

```sh
bend examples/indexed_window.bend -o build/indexed-window
./build/indexed-window
```

Use **A/D** to orbit, **W/S** to change elevation, **Q/E** to zoom, and **R** to reset. Press **Escape** or use the window's close button to exit.

Resizing recreates the swapchain, framebuffers and depth attachment and updates the camera aspect ratio. Unmapped or zero-sized windows keep processing events without acquiring images. One frame is in flight; acquisition, rendering and presentation fences complete before resources are reused. `Entry.with` cleans up on normal close or a returned error, and the example checks that no wrapper objects remain.

The mesh uses 28 position/color vertices (24-byte stride), 42 UINT32 indices and the existing GLSL shaders. A column-major 64-byte camera push constant uses Vulkan's depth range of 0 to 1 and flips projection Y. The floor is drawn after the cube so their overlap exercises depth testing.

The live-window verifier uses [bend-ui-test 0.1.0.1](https://hub.bend-lang.com/n/bend-ui-test) for input and [bend-window-capture 0.1.0.2](https://hub.bend-lang.com/n/bend-window-capture) for client pixels. Bend fetches these pinned packages on the first build. From the repository root, run:

```sh
bend examples/verify_window.bend -o build/verify-window
./build/verify-window
```

This opens and closes its own windows, checks rendered colors and camera changes, resizes through landscape and portrait sizes, unmaps/restores, and tests Escape and close while suspended. Logs and binary PPM captures are written under `build/indexed-window-*`. It enables Khronos and synchronization validation when the layer is installed. Python Xlib and Pillow are no longer needed. The headless suite remains independent of `DISPLAY`.

Keep the client unobscured and allow application-requested resizing. On a tiling desktop, use a floating window or an isolated X11 display (for example, rootful XWayland or Xvfb) and set `DISPLAY` for the verifier. Geometry and capture failures fail verification rather than skipping checks.

A small verification-only native adapter in `tools/window_verification/bridge.*` owns/reaps the child process and handles X11 discovery, resize and map/unmap. It lends a private capture connection to the capture package without transferring ownership of the Vulkan window. The adapter is pinned to the Bend 2.0.39 window ABI; revalidate it when upgrading Bend. Pixel assertions, exact camera-reset comparison, bounded polling and evidence output are implemented in Bend.

## Repository boundaries

| Area | Code and formal claims | Verification |
| --- | --- | --- |
| General Vulkan API | `Vulkan.bend`, `src/`, root laws and proofs | `build/verify` |
| General graphics examples | `examples/`, shared `shaders/`, example laws and proofs | `build/verify-examples` |
| Voxel consumer (separate repository) | [bend-voxel](https://github.com/aivv73/bend-voxel), under `vulkan/` | From bend-voxel: `python3 vulkan/tools/verify.py` |

The root verifier includes the general examples and needs only `bend-collections`.
`tools/check_layers.bend` enforces the import boundary. The dependency runs one way: bend-voxel depends on bend-vulkan.
This repository has no bend-voxel submodule.
The historical [Atelier demo and its verification commands](https://github.com/aivv73/bend-voxel/tree/main/vulkan/README.md)
remain available separately.

## Use the library

Published on BendHub as [bend-vulkan-library@0.1.0.0](https://hub.bend-lang.com/n/bend-vulkan-library),
owned by [aivv73](https://hub.bend-lang.com/user/aivv73).
Source: [bend-vulkan on Entire](https://entire.com/et/bend-engine/bend-vulkan).
Import the published API and helpers directly:

```bend
import bend-vulkan-library@0.1.0.0/Vulkan.bend as V
import bend-vulkan-library@0.1.0.0/src/core.bend as Core
import bend-vulkan-library@0.1.0.0/src/constants.bend as vk
import bend-vulkan-library@0.1.0.0/src/upload.bend as Upload
import bend-vulkan-library@0.1.0.0/deps/bend-collections/src/math/u64.bend as W
```

The package includes the native bridges, examples, and pure laws and proofs.
[package.bend](package.bend) collects these files for publication; use `Vulkan.bend` as the API entry.
The published release uses BendHub's default MIT-0 license for bend-vulkan and
preserves the bundled bend-collections module's MIT license.

Import [Vulkan.bend](Vulkan.bend) for the public API, [src/core.bend](src/core.bend) for selection helpers, and [src/constants.bend](src/constants.bend) for Vulkan constants.
Sizes, offsets, and alignments use the two-limb `U64` in [bend-collections](https://github.com/Giulio2002/bend-collections), at `deps/bend-collections/src/math/u64.bend`.
Import paths are relative to your Bend source file.

Start with the [buffer example](examples/buffer_roundtrip.bend). Its resource scope uses `V.Entry.with(Unit, entry => run(entry))` to load Vulkan and clean up after either success or a returned failure.
`V.Action(A)` is `IO(V.VkResult(A))`; `do V.Action<Unit>:` propagates returned failures.
Use `V.or_exit` at the application boundary. Calling `IO.die`, `IO.exit`, or `IO.try` inside the scope bypasses its cleanup callback.

Handles have distinct types and are copyable with Bend's `+` annotations. Dropping a handle does not destroy its Vulkan object.
The native registry checks ownership and liveness. Explicit destruction rejects live dependents; closing an entry releases its descendants in dependency order.
Callers remain responsible for Vulkan validity requirements for their flags, extensions, and resource use.

The [API reference](docs/api.md) documents supported operations and limits. The [design document](docs/design.md) explains native dispatch, the compiler ABI, and resource lifetimes.
General `pNext` chains, allocation callbacks, and platforms beyond Linux are outside the current scope.

## Verify changes

Verification follows [AGENTS.md](AGENTS.md): formal laws and executable proofs, real-runtime validation, live UI checks, and deterministic evidence. Traditional unit, integration, and mock-based tests are not maintained.

The headless verifier also requires `glslc` and `spirv-val` for shader freshness checks. Python 3 remains required by the binding and shader generators, which the Bend verifier invokes with `--check`. Verification runners and the import-boundary checker are Bend programs.

```sh
bend tools/verify.bend -o build/verify
./build/verify
```

The verifier checks generated files, import boundaries, and pure proofs (including the pixel-verification laws), then builds and runs the public examples for device discovery, buffer readback, image clears, and indexed color/depth rendering.
It enables Khronos and synchronization validation when the validation layer is installed. A missing Vulkan device fails verification.
Reports and captures go under `build/`, including `discovery.txt` and `validation.txt`.

To run the buffer, offscreen, and indexed examples under AddressSanitizer and UndefinedBehaviorSanitizer as well:

```sh
./build/verify --sanitize
```

Build the independent window verifier as shown above, then run `./build/verify-window`. Atelier acceptance remains in the [consumer suite](https://github.com/aivv73/bend-voxel/tree/main/vulkan/README.md#ownership-and-checks).
The root suite needs no `DISPLAY` and no files from bend-voxel.

Pure rules live in [LAWS.bend](LAWS.bend), with proofs in [PROOF.bend](PROOF.bend). Before committing, run:

```sh
bend PROOF.bend
```

These proofs cover pure functions, not native C code or GPU execution.
Voxel packing and appearance laws are kept in the consumer’s own `LAWS.bend` and `PROOF.bend`.

Bindings come from [tools/bindings.json](tools/bindings.json) and the checked-in registry extract. After changing the manifest, regenerate them:

```sh
python3 tools/generate.py
```

Shader words are checked in, so examples do not need a shader compiler to build. After editing GLSL, regenerate them with:

```sh
python3 tools/build_shaders.py
```
