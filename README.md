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

Check these examples independently with `python3 examples/verify.py`.

## Repository boundaries

| Area | Code and tests | Verification |
| --- | --- | --- |
| General Vulkan API | `Vulkan.bend`, `src/`, `tests/`, root laws and proofs | `python3 tools/verify.py` |
| General graphics examples | `examples/`, shared fixture `shaders/`; indexed and readback acceptance in `tests/` | `python3 examples/verify.py` |
| Voxel consumer (separate repository) | [bend-voxel](https://github.com/aivv73/bend-voxel), under `vulkan/` | From bend-voxel: `python3 vulkan/tools/verify.py` |

The root verifier includes the general examples and needs only `bend-collections`.
`tools/check_layers.py` enforces the import boundary. The dependency runs one way: bend-voxel depends on bend-vulkan.
This repository has no bend-voxel submodule.
The historical [Atelier demo and its verification commands](https://github.com/aivv73/bend-voxel/tree/main/vulkan/README.md)
remain available separately.

## Use the library

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

The headless library suite also requires `glslc` and `spirv-val` for shader freshness checks.

```sh
python3 tools/verify.py
```

The suite checks generated files and pure proofs, runs GPU readback and rendering comparisons, and exercises lifetime and failure handling.
It enables Khronos and synchronization validation when the validation layer is installed. A missing Vulkan device fails verification.
Reports and captures go under `build/`, including `discovery.txt` and `validation.txt`.

To include AddressSanitizer and UndefinedBehaviorSanitizer:

```sh
python3 tools/verify.py --sanitize
```

Native-window and Atelier acceptance are in the [consumer suite](https://github.com/aivv73/bend-voxel/tree/main/vulkan/README.md#ownership-and-checks).
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
