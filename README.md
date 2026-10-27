# bend-vulkan

A native Vulkan wrapper for Bend, inspired by [ash](https://github.com/ash-rs/ash).
The implementation provides explicit instance, device, buffer, image, memory, command-buffer, fence, render-pass, framebuffer, shader, and indexed graphics operations.
Vulkan 64-bit sizes, offsets, and alignments use the actual two-limb `U64` from [bend-collections](https://github.com/Giulio2002/bend-collections).

This is a 64-bit Linux Vulkan 1.0 subset with optional X11 presentation. It supports capability discovery, explicit barriers, packed array uploads, GPU transfers, fence-backed command reuse, color/depth attachment clears, and indexed depth-tested draws.
Images use a six-format, optimal-tiled 2D profile with explicit mips, layers, binding, views, and staging readback.
Reusable staging, checked source subranges, recorded-reference retirement, independent submissions and timestamp queries support repeated edits. The production consumer derives sparse chunks and greedy shadow geometry. X11 presentation requires `VK_EXT_swapchain_maintenance1`. Headless binaries keep the Vulkan 1.0 path and load no X11 library.
Uniform-buffer and combined-image-sampler descriptors support sparse bindings, arrays, and normalized samplers. Recorded sets stay frozen until command reset. Callbacks and general `pNext` chains are not implemented.

## Run the buffer example

Use Linux with glibc 2.34 or newer. Install Bend **2.0.39**, Clang, Python 3, Vulkan development headers, `libvulkan.so.1`, and a Vulkan driver.
Run `bend update` to upgrade an existing Bend installation, then confirm `bend version` prints `bend 2.0.39`.
A hardware driver or a software ICD such as Lavapipe can provide the device.
The examples select a graphics queue for transfer commands.
Production verification also requires Python NumPy and Pillow. Production rendering requires sampled D32 support.

Initialize the pinned dependencies:

```sh
git submodule update --init --recursive
```

Build and run the native example:

```sh
mkdir -p build
bend examples/buffer_roundtrip.bend -o build/buffer-roundtrip
./build/buffer-roundtrip
```

Expected output:

```text
Host roundtrip and GPU buffer fill verified
```

The example writes four bytes to Vulkan memory and checks their readback.
It then records `vkCmdFillBuffer`, submits the command buffer, waits for completion, and checks sixteen bytes against the value `42`.
Build and run `examples/discover.bend` the same way to list layers, extensions, devices, heaps, format masks, and selected limits.
It prints U64 values as low/high limbs.

## Run the image example

Build and run the offscreen example after initializing the dependency:

```sh
bend examples/offscreen_roundtrip.bend -o build/offscreen-roundtrip
./build/offscreen-roundtrip
```

Expected output:

```text
Optimal RGBA8 image clear and every-pixel readback verified
```

The example queries the exact image configuration and clears a 4 by 4 RGBA8 image to magenta.
It transitions the image, copies all 64 bytes to a host-readable buffer, waits for fence completion, and compares every pixel.
The bytes are row-major `R,G,B,A`, with `y=0` as the first row. The example defines that row as the top.
Optimal image memory has no public linear pixel stride. Readback uses a buffer with explicit copy strides.

`bend example.bend` uses Bend's JavaScript backend. Vulkan effects report a native-build-required error in that backend.

## Run indexed graphics

Build and run the indexed example:

```sh
bend examples/indexed_offscreen.bend -o build/indexed-offscreen
./build/indexed-offscreen
```

It compares every RGBA8 and D32 pixel for overlapping red and green surfaces in both draw orders.
Both UINT16 and UINT32 indices use nonzero offsets and base vertex -3. A nonsymmetric column-major camera matrix transforms the mesh.
The [graphics contract](docs/api.md#example-mesh-and-camera-contract) defines byte strides, matrix order, depth, winding, and image orientation.
GLSL and mesh packing belong to the example. The wrapper accepts configurable vertex input, rasterization, depth comparison, color masks, and generic push words.

The shader words are checked in. The complete verifier also requires `glslc` and `spirv-val`.
To rebuild the words after editing GLSL, run:

```sh
python3 tools/build_shaders.py
```

## Run the voxel consumer

Build the pinned dense-body consumer and export the intact and carved cube:

```sh
bend examples/voxel_offscreen.bend -o build/voxel-offscreen
./build/voxel-offscreen
```

It writes 512 by 512 frames to `build/voxel-intact.ppm` and `build/voxel-carved.ppm`.
It also exports the reset/empty frames and the pinned upstream renderer's visual references.
The [voxel contract](docs/voxel.md) defines packing, projection, edge comparison, ownership, and verification limits.
Actual GPU checks cover full U32 material bytes, all six directions, edits, empty meshes, and camera frames without mesh uploads.
The reference renderer runs on the CPU. CUDA is not a prerequisite.

## Run the Atelier scene

Build and run the native X11 consumer:

```sh
bend examples/voxel_interactive.bend -o build/voxel-interactive
./build/voxel-interactive
```

The default scene is the full pinned Atelier with `Camera.atelier()`, linear material lighting, sun shadows, gradient, ground and grid. A fixed 20 cm brush marks exact selected cells yellow and draws three depth-aware rings.
Use WASD and Q/E to fly. Hold RMB to look. Left click carves the hovered surface. Space cuts the current hover. R restores the original scene while retaining the camera.
Escape and the native window close button exit. Resize and minimize preserve world state. Ordinary runs are quiet; `--trace` enables verification diagnostics.

Atelier uses two independent frame slots by default. `--slots=1` selects one slot, and `--slots=2` selects two. Each slot freezes its own camera, appearance and shadow resources after acquisition completes. Camera-only frames reuse the installed geometry. Bend's runtime options go between `+RTS` and `-RTS`: `./build/voxel-interactive +RTS --threads 4 -RTS --slots=2` selects four CPU workers independently of the slot count.

Use `./build/voxel-interactive --cube` for the earlier basic cube mode. Its Space key retains the fixed demo cut. The [presentation contract](docs/presentation.md) describes ownership, input and completion.

![Actual default Atelier application window with brush preview](docs/atelier-interactive.png)

Generate the original reference records, then run production offscreen acceptance and export actual RGBA8, camera D32, shadow D32 and PNG captures:

```sh
python3 tools/check_reference_lighting.py
python3 tools/check_production.py --sanitize
```

Direct production checks require the original reference records at `build/milestone-6-reference/receivers.jsonl`; run the reference checker first.

The offscreen and native owners use the same production recorder. Captures and reports remain under `build/milestone-6-production/`. The [voxel contract](docs/voxel.md) separates exact state and identity checks from bounded appearance comparisons.

## Use the API

Import `Vulkan.bend`, `src/core.bend`, `src/constants.bend`, and the dependency's `src/math/u64.bend` with paths relative to your program.
The executable [buffer example](examples/buffer_roundtrip.bend) shows allocation and fill submission.
The [repeated transfer check](tests/repeated.bend) shows packed upload, explicit barriers, general submission, finite completion, and reset/re-recording.
The [rendering check](tests/rendering.bend) shows Vulkan 1.0 color/depth passes, partial-area clears, and framebuffer-only lifetime protection.
The [indexed graphics acceptance](tests/indexed_graphics.bend) checks clipping, winding, viewport/scissor, changing pushes, lifetime, and 32 stable reuses.
The [image reuse check](tests/image_repeated.bend) runs 32 changing color/depth passes and 32 resource churn cycles.

`V.Action(A)` is `IO(V.VkResult(A))`. A `do V.Action<Unit>:` block propagates returned failures.
`V.Entry.with(Unit, entry => run(entry))` loads the Vulkan library, runs your callback, and closes its resource tree after either `Done` or `Fail`.
Use `V.or_exit(Unit, result)` at the application boundary to report the final result.
Calling `IO.die`, `IO.exit`, or `IO.try` inside a resource scope bypasses that cleanup callback.

Handle values are copyable with Bend's `+` annotations. Each handle kind has a distinct type.
Native code validates registry keys, object kinds, ownership, and liveness before it calls Vulkan.
Explicit destroy operations reject live dependents. `Entry.close` releases descendants in dependency order.
Dropping a Bend handle value does not destroy its Vulkan object.

See [the API reference](docs/api.md) for supported operations and [the design](docs/design.md) for the FFI and ownership decisions.
See the [roadmap](docs/roadmap.md) for milestone status and remaining renderer work.

## Verify changes

Verification requires Python 3 with NumPy and Pillow, `glslc`, `spirv-val`, and `vulkaninfo` from vulkan-tools, in addition to the native build dependencies above. Presentation checks also require X11 development headers/runtime, rootful Xwayland for `--isolated-display`, and ImageMagick `import`.

Run the generator check, proof gate, native examples, and negative integration checks:

```sh
python3 tools/verify.py
```

To include address and undefined-behavior sanitizers:

```sh
python3 tools/verify.py --sanitize
```

Require native-window acceptance as well as the complete headless suite:

```sh
python3 tools/verify.py --sanitize --presentation
```

On a Wayland desktop, an isolated X11 display avoids other applications' pointer grabs:

```sh
python3 tools/verify.py --sanitize --presentation --isolated-display
```

This option requires rootful Xwayland. Window verification also requires Python Pillow and ImageMagick `import`.
Presentation checks run only with `--presentation`. The default suite remains usable without `DISPLAY`.

The native checks include 32 alternating packed uploads copied through a device-local intermediate GPU buffer to literal readback bytes.
They reuse command/pool/fence objects, check stable row counts, and reject pending reset, destruction, mapping, and further submission before observing completion.
Separate checks cover fence status/wait/idle completion, retained references, stale/wrong-owner keys, and zero remaining objects after successful and accepted-pending failure scopes.
Native and interpreted probes read the returned upload array after success and rejection.
Image checks compare every color/depth pixel, nonuniform padded two-layer copies at a nonzero mip, and untouched pixels and buffer sentinels.
They cover RGBA/BGRA UNORM/SRGB channel order, D32 depth `0.5`, and D16 depth `1.0` readback.
Pass tests establish layouts in a separate completed and reset recording before submitting only framebuffer begin/end.

`tools/check_native.py` adds controlled dispatch/allocation probes only to emitted test C.
These exercise submit OOM/uncertainty, wait/idle/reset errors, map/flush failure ownership, metadata allocation failures, enumeration retries, composite ABI, private-fence isolation, and sticky device loss.
Injected results are distinct from real GPU execution. The tests never provoke hardware loss.
The sanitizer run includes those probes, the real repeated transfer test, and indexed graphics acceptance.
The emitted-test allocator counts all wrapper metadata allocations, and teardown asserts both zero metadata allocations and zero registry rows.
Driver-global leak detection is disabled for ASan. These explicit counters cover wrapper cleanup.
The verifier records queried device/layer output in `build/discovery.txt` and validation availability in `build/validation.txt`.
When Khronos validation is installed, it also runs the real GPU checks with synchronization validation enabled.
A missing driver or device fails native verification. It is not a passing skip.
Bend's pure laws live in `LAWS.bend`; their proofs live in `PROOF.bend`.
Before committing, run `bend PROOF.bend`. For the additional proof-kernel check, run `bend PROOF.bend --verdict`.
The normal checker accepts the retained laws. The optional independent kernel has a mismatch on the unchanged 3,072-quad index-bound law, also present on the baseline. No assertion or proof range is reduced to avoid it.
The laws cover pure functions. They do not verify C code, Vulkan drivers, or GPU execution.

`tools/bindings.json` defines the supported effects. `tools/generate.py` generates their Bend declarations, native registrations, JavaScript errors, and selected core constants from the checked-in Khronos registry extract.
Run `python3 tools/generate.py` after changing the manifest. The generator does not implement new native commands or translate arbitrary Vulkan structs.

The milestone-3 run on NVIDIA GeForce GTX 1660 passed `python3 tools/verify.py --sanitize` with Khronos and synchronization validation available.
Optimal color image requirements exposed no compatible host-visible memory type on that device.
Real lifetime rejection and pixels use the driver and staging. Post-completion mapped access in the graph probe uses controlled dispatch and is labeled separately.
Noncoherent cache paths have controlled flush-failure coverage. Their driver coverage depends on the selected memory type.

The milestone-4 consumer also passes the complete sanitize suite on that device, including whole-frame reference checks, GPU metadata diagnostics, bounded edits, and zero-row cleanup.
Its native translation unit preprocesses and builds without CUDA support.

Milestone 6 acceptance passed the complete sanitizer and isolated-display presentation gate on NVIDIA GeForce GTX 1660 with Khronos and synchronization validation. The separately executed pure shadow-causality gate uses the same actual captures. See `build/milestone-6-appearance-verification.log`, `build/milestone-6-shadow-causality-verification.log` and `build/milestone-6-production/shadow-causality/results.json`.

Milestone 7 implementation acceptance passed `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display` on the same device. The complete log is `build/milestone-7-final-verification.log`. It includes sparse chunk coverage, independent original-Body checks, atomic retirement rollback, two pending submissions, full acquisition-time uniforms, distinct shadow readbacks, ordered presentation, resize and suspension, and quiet launches without timing output. Native windows cover queue pairs 0/0 and 0/2.

The [milestone 7 evidence](.audit/m7-results.md) retains build provenance, correctness results, the separate profile and timing limits. Old/new static outputs are ineligible for timing comparison. No implementation speedup is demonstrated. CPU and slot sweeps compare configurations of the same binary.
