# Vulkan wrapper roadmap

The target is an ash-inspired Bend wrapper that can run bend-voxel as a mesh renderer.
Bend owns the world, edits, meshing, and application state. GLSL vertex and fragment shaders run through Vulkan graphics pipelines.
The first renderer milestone is a headless, indexed mesh draw with color and depth readback. Window presentation follows that working path.

Milestones are ordered by dependency and observable results. They are not release dates.
Milestones 0 through 7 are implemented. Later milestones describe planned capabilities and proposed API names.

## Delivery order

| Milestone | Status | Wrapper capability | Acceptance result |
| --- | --- | --- | --- |
| 0. Native foundation | Implemented | Loader, checked handles, buffers, memory, synchronous fill | Exact host and GPU buffer readback |
| 1. General transfers and completion | Implemented | Bulk uploads, explicit barriers, buffer copies, fences, command reuse | Repeated upload, copy, and readback with bounded live resources |
| 2. Offscreen images | Implemented | Images, binding, views, barriers, color/depth passes, readback | Every-pixel and repeated color/depth clears with bounded resources |
| 3. Indexed graphics | Implemented | SPIR-V modules, graphics pipelines, vertex/index binding, depth testing, push constants | Every-pixel RGBA8/D32 occlusion in both orders, both index widths, clipping, camera updates, and stable reuse |
| 4. Voxel mesh consumer | Implemented | Complete the minimal mesh-drawing API through a real consumer | Intact and carved 8³ cube exported at 512×512 |
| 5. Interactive presentation | Implemented | Native surfaces, swapchains, acquire/submit/present, frame lifecycle | Editable cube runs in a Vulkan window |
| 6. Full scene and appearance | Implemented | Descriptors, uniforms, sampled images, samplers, shadow passes | Atelier scene, materials, ground, shadows, and brush preview |
| 7. Repeated edits and throughput | Implemented | Sparse chunks, reusable uploads, atomic retirement, independent frames and diagnostics | Exact geometry, bounded appearance, stable repeated edits and scoped configuration measurements |
| 8. Library breadth and portability | Planned | Broader generated bindings, negotiated extensions, additional platforms | Documented support verified on additional drivers and applications |

The first public renderer checkpoint is milestone 4. The first interactive renderer checkpoint is milestone 5.

## 0. Native foundation

The current implementation provides these capabilities:

- [x] Entry, instance, and device dispatch with distinct checked handle types.
- [x] Device, queue-family, and memory-type discovery.
- [x] Explicit buffer creation, memory requirements, allocation, binding, and destruction.
- [x] Bounds-checked host byte copies, including noncoherent cache handling.
- [x] One-shot command buffers, GPU buffer fills, and synchronous submission.
- [x] Scoped cleanup, stale-handle rejection, ownership checks, and U64 boundary checks.
- [x] A pinned `bend-collections` dependency for every Vulkan size, offset, and alignment.
- [x] Generated effect declarations, registrations, selected constants, and native-only JavaScript errors.

The baseline targets Bend 2.0.39 and 64-bit Linux. The initial Vulkan API level is 1.0.
The generator currently consumes a small enum extract and an effect manifest. It does not generate arbitrary Vulkan structs or dispatch tables.
Milestone 0 provides one selected queue. Milestone 3 adds graphics pipelines.

## 1. General transfers and completion

This milestone is complete. Transfers use explicit barriers, owned packed uploads, fence completion, and individual command reset.

Wrapper work:

- [x] Make command-buffer end finish recording without inserting a transfer-to-host barrier. Move that barrier into the fill caller.
- [x] Expose buffer and memory barriers with explicit stage and access masks.
- [x] Add buffer copies and a packed bulk-upload path with explicit byte length and Bend array ownership.
- [x] Add queue submission with fences, fence wait/status/reset, and individual command-buffer reset.
- [x] Distinguish recording, executable, pending, completed, and invalid command states. Prevent reset or resource destruction while work is pending.
- [x] Track resources referenced by recorded commands and release those references on reset or pool destruction.
- [x] Query instance layers, instance/device extensions, required limits, memory heaps, and format support as the following milestones need them.
- [x] Keep `submit_and_wait` as a convenience over the general submission path. Migrate existing callers together with the implementation.

Start with one queue and one submission in flight. Add additional queue selection when presentation requires it.
Use legacy Vulkan 1.0 synchronization for this baseline. Newer synchronization APIs require a separate negotiated capability.
The [Khronos synchronization guide](https://docs.vulkan.org/guide/latest/synchronization_examples.html) links both modern and legacy examples.

Completion evidence: repeatedly upload packed data, copy it through GPU buffers, and verify the exact readback after fence completion.
Reuse command resources and verify that the live-object count does not grow.
Exercise pending-resource protection and failure cleanup through actual native execution.
The existing fill example must continue to pass with its barrier expressed explicitly.

Acceptance passed with `python3 tools/verify.py --sanitize` on NVIDIA GeForce GTX 1660 with Bend 2.0.37.
The verifier ran 32 changing packed staging uploads through a device-local intermediate buffer to literal host readback bytes.
Command/pool/fence rows stayed fixed. A further 32 convenience submissions reused one private fence.
Native success and accepted-pending failure scopes left zero registry rows.
Controlled test-only probes covered exact error bits, array ownership, failed metadata allocation, submit uncertainty, reset failure, and sticky loss.
They did not induce hardware loss. Khronos validation and synchronization validation were unavailable.
Rerun evidence is in `tools/verify.py`, `tools/check_native.py`, and the native Bend/C checks under `tests/`.

## 2. Offscreen images

This milestone is complete. Image layouts, allocations, copy strides, and synchronization remain explicit.
Vulkan 1.0 render-pass begin/end and attachment load clears belong to this milestone. Graphics draws belong to milestone 3.

Wrapper work:

- [x] Add image creation/destruction, memory requirements, allocation binding, and image views.
- [x] Add image layouts, aspect masks, subresource ranges, explicit image barriers, and supported-format queries.
- [x] Add color and depth attachment support through Vulkan 1.0 render passes and framebuffers, including begin/end and load-operation clears.
- [x] Add image clears, buffer-to-image copies, and image-to-buffer readback.
- [x] Extend cleanup to image views, framebuffer references, images, and their allocations.
- [x] Define readback dimensions, row stride, channel order, and color encoding explicitly.

Select supported formats from queries. Use staging readback so the example does not depend on directly mapping an optimal-tiled image.

Completion evidence: clear a color target, transition it for transfer, copy it to a host-readable buffer, and verify every pixel.
Repeat the sequence and destroy every object in its valid dependency order.
Verify unsupported format requests and wrong-device objects produce useful errors.

Acceptance passed with `python3 tools/verify.py --sanitize` on NVIDIA GeForce GTX 1660 with Bend 2.0.37.
The six-format creation profile is optimal 2D RGBA8/BGRA8 UNORM/SRGB and depth-only D16_UNORM/D32_SFLOAT, with one sample and explicit mip/layer counts.
The [offscreen example](../examples/offscreen_roundtrip.bend) verifies every magenta RGBA8 pixel through staging.
The [transfer check](../tests/offscreen.bend) verifies asymmetric padded two-layer uploads at nonzero offsets and mip, untouched texels, and all staging sentinels.
The [rendering check](../tests/rendering.bend) verifies full and partial-area color/D32 clears and LOAD preservation.
The [format check](../tests/image_formats.bend) verifies RGBA/BGRA UNORM/SRGB raw channels and exact D16 depth `1.0` bytes.
D32 clear and render-pass readback verify depth `0.5` as `00 00 00 3f` at every pixel.
The [reuse check](../tests/image_repeated.bend) verifies 32 changing color/depth pass cycles and 32 image/view/pass/framebuffer churn cycles with bounded rows.

Framebuffer-only lifetime checks establish layouts in an earlier completed and reset recording.
Real pre-observation host calls reject through the transitive graph, while unrelated staging memory remains accessible.
Controlled emitted-C probes verify timeout/NOT_READY, Uncertain recovery, failed reset references, allocation/driver rollback, and zero metadata allocations after cleanup.
Optimal color requirements expose no compatible host-visible memory type on this GPU. Post-completion mapped access is separately controlled evidence.
Khronos validation and synchronization validation were unavailable. Driver-global leak detection is disabled, with explicit wrapper row and metadata counters.
The [API reference](api.md#images-and-views) specifies supported usages, binding overlap/granularity policy, raw bytes, copy strides, and caller layout responsibilities.

## 3. Indexed graphics

This milestone is complete. Indexed draws use the existing Vulkan 1.0 passes and checked lifetime graph.

Wrapper work:

- [x] Load SPIR-V words into shader modules. Keep GLSL compilation in the build process.
- [x] Add pipeline layouts and a small camera push-constant path.
- [x] Add graphics pipeline creation with vertex input, triangle topology, rasterization, depth testing, and color output state.
- [x] Add viewport/scissor, pipeline binding, vertex/index buffer binding, push constants, and indexed draws.
- [x] Extend command reference tracking to the resources used by graphics draws.
- [x] Document byte strides, attribute formats, index types, matrix layout, coordinate conventions, and shader alignment.

The first example uses a combined camera matrix and flat colors. Descriptors and textures are not prerequisites for that example.
The mesh layout and shaders belong to the example or renderer. The wrapper exposes configurable Vulkan descriptions.
Khronos documents the [indexed draw path](https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/03_Index_buffer.html) and [depth attachments](https://docs.vulkan.org/tutorial/latest/07_Depth_buffering.html).

Completion evidence: draw indexed geometry into the offscreen target and verify its coverage and colors.
Render overlapping geometry in both draw orders and verify that the nearer surface wins.
Check winding, clipping, depth convention, and image orientation before introducing voxel geometry.

Executed acceptance is in [indexed_graphics.bend](../tests/indexed_graphics.bend) and [graphics_probes.c](../tests/graphics_probes.c).
Every RGBA8 and D32 pixel matches literal expectations for both draw orders, UINT16/UINT32 indices, nonzero offsets/firstIndex, and base vertex -3.
The suite checks winding, lateral and near/far plane clipping, positive-height orientation, a nonsymmetric column-major matrix, dynamic viewport/scissor, color masks, triangle strips, changing pushes, and 32 stable reuses.
Real submissions retain overwritten pipeline/buffer roots and exclude host access until observed completion.
Controlled dispatch separately checks INT32_MIN, high U64 limbs, effective memory-plus-relative binding alignment, allocation-before-dispatch, partial pipeline outputs, Uncertain recovery, and failed-reset retention.
Success and deliberate callback-failure scopes clean up all rows and wrapper metadata.
`python3 tools/verify.py --sanitize` and `bend PROOF.bend` pass on GTX 1660 with Khronos and synchronization validation available.
The wrapper checks index byte spans and first-record vertex coverage. Shader semantics, index contents, and subsequent vertex/instance fetch bounds remain caller obligations.

## 4. Voxel mesh consumer

This milestone integrates the wrapper with bend-voxel. It does not add meshing policy to the wrapper.

Renderer work:

- [x] Define a packed vertex/index contract shared by the Bend mesher and GLSL shaders.
- [x] Convert the dense body's exposed faces into indexed quads, retaining face direction and material identity.
- [x] Start with four vertices and six indices per quad. Share vertices or merge quads in a later optimization.
- [x] Rebuild and upload the mesh after carving or reset. Camera movement updates camera parameters without rebuilding geometry.
- [x] Export intact and carved 8³ cube frames at 512×512 through the offscreen graphics path.
- [x] Check complete exposed-face coverage, absence of interior faces, index bounds, outward winding, and preserved materials.

The existing [geometry module](https://github.com/aivv73/bend-voxel/blob/cdfd92d356229c5de5f4aaddd358f15ec3686dd4/voxel.bend) contains both unit `Face` values and larger `Rectangle` values.
Its dense-body path extracts exposed faces. Its cuboid path emits six rectangles per cuboid.
Before using the cuboid path for the full scene, resolve shared and overlapping boundaries. Those rectangles alone do not establish the exterior of their union.

Completion evidence: formal mesh properties and native rendered output agree on the intact and carved cube's geometry and materials.
Keep the existing renderer as a visual reference. Compare rasterization edge coverage under a stated policy rather than assuming identical floating-point pixel output.
Milestone 4 used basic material colors. Milestone 6 adds production shadows and brush overlays.

Acceptance passed with `python3 tools/verify.py --sanitize` on NVIDIA GeForce GTX 1660 with Khronos and synchronization validation enabled.
The [consumer](../examples/voxel_offscreen.bend) exports intact and metric-demo-carved 8³ cubes at 512×512, plus reset, empty, and unchanged upstream renderer references.
Independent occupancy enumeration and decoded packed geometry checks verify all 384 intact and 396 carved quads, materials, both triangle windings, and indices.
Whole-frame basic color/D32 and full-U32-material/direction diagnostic readbacks pass the [fixed edge policy](voxel.md#verification-policy), including all six directions and high-bit IDs through `0xffffffff`.
Camera-only frames preserve mesh bytes and upload counts. Repeated carve/reset replacements have bounded live resources, empty geometry owns no mesh buffers, and scope cleanup leaves zero rows.
Pure packing, quad, count, and fixture-bounded index laws pass `bend PROOF.bend`.
The pinned upstream submodule is unmodified. Its visual renderer runs directly on the CPU, and preprocessing plus native artifact inspection confirm no CUDA prerequisite.
Vulkan core and native implementation remain unchanged.

## 5. Interactive presentation

Wrapper work:

- [x] Add a narrow native window-to-surface adapter, initially for Linux/X11, with explicit window and surface lifetimes.
- [x] Add surface capabilities, formats, present modes, and presentation-support queries.
- [x] Select graphics and presentation queues from actual support. Handle separate families when the selected device requires them.
- [x] Add swapchain creation, borrowed swapchain image handles, image views, acquire, present, and recreation.
- [x] Add binary semaphores and submission wait/signal lists. Track presentation-related resource lifetimes separately from rendering fence completion.
- [x] Handle suboptimal and out-of-date results as lifecycle outcomes. Handle minimized or zero-sized windows without a busy loop.
- [x] Keep native events and pointer capture available while Vulkan owns presentation.

Begin with one frame in flight. Add overlap after the ownership and synchronization behavior is verified.
Normal frames use fences and semaphores. Queue-idle waits remain available for simple tools and explicit shutdown paths.

Renderer work: preserve movement, mouse look, carving, reset, and close behavior through the new presentation boundary.
At the historical milestone 5 checkpoint, brush preview was deferred to milestone 6.

Completion evidence: drive a real native window through camera movement, edits, recreation, and close.
Verify frame ownership, continued input delivery, repeated recreation, and zero remaining wrapper objects after shutdown.

Acceptance passed with `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display` on NVIDIA GeForce GTX 1660.
The complete old headless suite, presentation ABI, literal semaphore readback, controlled failures, and native window checks passed with Khronos and synchronization validation.
The actual queue combinations were graphics and presentation 0/0 and 0/2. The native driver verified flight, relative look, click and demo cuts, reset, repeated landscape/portrait resize, focus-loss capture release, unmap/restore, continued input, and close while suspended.
Each native run ended with zero wrapper rows and zero tracked native metadata allocations. App-only PNGs and logs remain under `build/window-*`.
The [presentation contract](presentation.md) defines maintenance1 fence completion, explicit acquisition leases, borrowed-image lifetimes, rollback, viewport mapping, and the Linux/X11 support boundary.
The historical cube checkpoint remains an explicit regression mode; milestone 6 adds the production preview.

## 6. Full scene and appearance

Wrapper work:

- [x] Add descriptor-set layouts, pools, allocation, updates, binding, uniform buffers, and sampled-image bindings.
- [x] Add samplers and depth-image sampling needed for a shadow pass.
- [x] Support the transitions and dependencies between shadow rendering, sampling, color rendering, and readback or presentation.
- [x] Protect descriptor contents and referenced resources while submissions use them.

Renderer work:

- [x] Export the full Atelier scene as a correct exterior mesh, including material boundaries and existing rectangular faces.
- [x] Port material palette behavior, directional light, sky ambient light, ground, and grid.
- [x] Restore sun shadows with an explicit image-comparison policy for differences from the existing cached lighting fields.
- [x] Keep lighting calculations in linear RGB and encode display output once.
- [x] Restore picking, exact brush selection, tint, and depth-aware brush rings. Keep cell/material identity available independently of merged triangle geometry.

Completion evidence: validate full and carved scenes, several camera poses, unsupported material diagnostics, lighting, shadows, and brush interaction.
Compare world and surface state exactly. Record any intentional appearance differences separately from geometry correctness.

The completed native default is Atelier with `Camera.atelier()`, exact 20 cm selection and depth-aware rings. `--cube` retains the older basic renderer with 64-byte push constants. Body is edit authority; CPU geometry updates before the next queued event, and acquisition-fence success atomically installs the latest geometry and matching appearance frame. Stable scene resources survive target recreation.

Acceptance passed the complete `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display` gate, plus the separately executed pure shadow-causality port on the same final actual captures. Khronos and synchronization validation and real ASan/UBSan device runs passed. Default Atelier windows with shared and distinct queue families exercised queue pairs 0/0 and 0/2. Logs and real images remain under `build/milestone-6-*`; the [voxel contract](voxel.md#production-appearance-and-evidence) records exact counts, selected shadow-depth witnesses, causal bounds, cached and direct visibility distinctions and proof limits. Both pinned Atelier and production shadows use effective 512-square depth. No unexplained selected shadow differences or masked identity errors are accepted.

## 7. Repeated edits and throughput

Wrapper work:

- [x] Add reusable staging storage, checked source and destination subranges, and deferred release after recorded references disappear.
- [x] Atomically retire every obsolete allocation in a generation, with rollback on rejection and collection after owner selection.
- [x] Support independent frames without overwriting earlier camera, appearance, shadow or command resources. Order present calls by submission sequence.
- [x] Add owned timestamp queries and clearly scoped monotonic diagnostics. Unsupported or unavailable timing preserves rendering.

Renderer work:

- [x] Derive sparse chunks from authoritative Body state. Rebuild dirty chunks, neighboring exterior owners and remote source domains changed by splitting.
- [x] Keep huge valid cuboids analytic and parallelize independent chunk builds with deterministic ordering.
- [x] Feed greedy rectangles to production shadow geometry while retaining canonical color and picking anchors, extents and source order.
- [x] Verify repeated cuts, empty-after-edit, reset, camera-only reuse, two pending slots and safe resize, suspension and cleanup.

The complete `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display` command passed on NVIDIA GeForce GTX 1660 under Linux/X11. Khronos and synchronization validation, actual ASan/UBSan execution, shared queue pair 0/0 and split pair 0/2 passed. The [milestone 7 evidence](../.audit/m7-results.md) retains the complete log, build provenance, review dispositions and measurement reports. The [voxel contract](voxel.md#sparse-chunks-and-frame-generations) describes geometry and appearance limits.

The old/new comparison is output-ineligible. All 20 processes exited zero and all 160 cut/reset actions completed, including warmup. Every one of 90 static RGB capture pairs differs at four pixels, with a maximum channel delta of four. Geometry and view fields match. All ten timing pairs remain excluded. No implementation speedup or regression is demonstrated.

The following sweeps use the same ordinary release binary on both sides. Each workload has five alternating eligible pairs and no failures. Each sweep completes 160 edit actions, including warmup. Values are medians with ranges across five runs. Cut and reset values use each run's median of six measured actions.

With one frame slot fixed:

| CPU workers | Observed handoffs/s | Cut latency, ms | Reset latency, ms |
| --- | --- | --- | --- |
| 1 | 42.44, 42.36 to 42.86 | 1207.5, 1202.0 to 1231.4 | 9483.1, 9373.3 to 9537.9 |
| 6 | 41.32, 41.05 to 43.16 | 1669.2, 1645.3 to 1682.5 | 4034.1, 3998.1 to 4044.3 |

One worker has lower observed cut latency, and six have lower reset latency. Flight ranges overlap. This mixed result selects no universal worker count.

With six CPU workers fixed:

| Frame slots | Observed handoffs/s | Cut latency, ms | Reset latency, ms |
| --- | --- | --- | --- |
| 1 | 41.80, 41.48 to 42.13 | 1666.1, 1638.9 to 1681.8 | 4010.4, 3980.5 to 4094.7 |
| 2 | 43.81, 43.20 to 44.39 | 1687.5, 1667.5 to 1716.6 | 4064.8, 4000.1 to 4128.2 |

Two slots have a higher observed handoff rate in this traced configuration. Cut and reset ranges overlap. The existing two-slot default and Bend's automatic worker default remain unchanged. These results establish neither a universally tuned production configuration nor an implementation speedup.

Handoffs count observed matching presentation-resource fences, which can signal before full presentation completes. Physical scanout is unmeasured. Flight runs share scripted input duration, while time-driven poses and per-frame GPU work can differ. Edit latency includes event dispatch through observation of the requested completed revision. Trace overhead, application logging delay and scheduling contributions are unmeasured. Observed polling gaps and read durations bound observer resolution only.

The separate four-run profile passed. Whole-run producer recording/submission has a median near 20.5 ms. Main-pass inclusive GPU medians are 0.601 and 0.624 ms in the two flight runs, and 1.431 and 1.441 ms in the two edit runs. Upload and shadow medians stay below 1 ms in all four runs. Long edit/event calls and whole-run CPU observations also identify host work. CPU scopes can realize deferred pure Bend work, and their run-wide medians include empty polls, warmup and settling. Isolated meshing cost is unavailable. GPU TOP-to-BOTTOM windows can overlap and cannot be added to each other or CPU samples. The observer and active desktop also consume resources.

Automatic allocation pooling, additional culling and additional draw batching remain conditional and deferred. No additional optimization has an independently verified win from these runs. Further batching must preserve canonical draw order and immutable generation ownership. Manual memory suballocation was available before this milestone. No shadow-history cache is implemented.

## 8. Library breadth and portability

Extend the wrapper through verified applications after the mesh renderer works:

- [ ] Expand the pinned registry input beyond the current enum extract and generate more enums, typed flags, structs, and dispatch metadata.
- [ ] Generate supported bindings from explicit marshalling policies. Reject unsupported pointer shapes instead of emitting placeholder bindings.
- [ ] Separate extension loading by dispatch level and negotiate requested features and API versions.
- [ ] Add useful extension chains, pipeline caches, indirect draws, and additional resource types as consumers require them.
- [ ] Add compute pipelines when an application needs compute, including possible future mesh generation.
- [ ] Add Wayland and other platform adapters with their own runtime verification. Keep platform details outside core renderer algorithms.
- [ ] Verify a documented driver/platform matrix and define the supported Bend compiler ABI policy.

Full Vulkan coverage, automatic shader translation, and compatibility with every ash feature are outside the first renderer release.

## Rules for every milestone

Keep Vulkan resource decisions explicit and the wrapper independent of voxel-domain types.
Use the pinned `bend-collections` U64 for Vulkan 64-bit integers, including future 64-bit masks. Preserve exact Vulkan result bits and useful operation diagnostics.

Each new handle kind needs ownership, destruction, recorded-reference, pending-work, and failure-cleanup behavior.
Validate external inputs at the native boundary. Do not claim that handle checks make every Vulkan operation safe.
Build shader binaries for the selected target and document the shader data layout.

Extend the existing generator and native verification as each capability lands.
Keep pure invariants in `LAWS.bend` and their proofs in `PROOF.bend`. Native effects and driver execution require runtime evidence.
Inside bend-voxel, follow its project instructions for formal properties, actual runtime checks, and UI evidence.

Use Vulkan validation, including synchronization validation, when available. Record which driver and validation facilities were used and which were unavailable.
Run the applicable examples and generator freshness check. Run `bend PROOF.bend` before committing.
For native boundary changes, run the relevant sanitizer checks.
Finish each milestone's acceptance result before starting its dependent milestone.

## Start here

Milestone 7 is complete within its documented Linux/X11 and measurement scope. Milestone 8 extends binding breadth and portability. Preserve the exact geometry, bounded appearance, shadow-causality and native presentation gates as new consumers are added.
