# Vulkan wrapper roadmap

The target is an ash-inspired Bend wrapper that can run bend-voxel as a mesh renderer.
Bend owns the world, edits, meshing, and application state. GLSL vertex and fragment shaders run through Vulkan graphics pipelines.
The first renderer milestone is a headless, indexed mesh draw with color and depth readback. Window presentation follows that working path.

Milestones are ordered by dependency and observable results. They are not release dates.
Milestones 0 through 3 are implemented. Later milestones describe planned capabilities and proposed API names.

## Delivery order

| Milestone | Status | Wrapper capability | Acceptance result |
| --- | --- | --- | --- |
| 0. Native foundation | Implemented | Loader, checked handles, buffers, memory, synchronous fill | Exact host and GPU buffer readback |
| 1. General transfers and completion | Implemented | Bulk uploads, explicit barriers, buffer copies, fences, command reuse | Repeated upload, copy, and readback with bounded live resources |
| 2. Offscreen images | Implemented | Images, binding, views, barriers, color/depth passes, readback | Every-pixel and repeated color/depth clears with bounded resources |
| 3. Indexed graphics | Implemented | SPIR-V modules, graphics pipelines, vertex/index binding, depth testing, push constants | Every-pixel RGBA8/D32 occlusion in both orders, both index widths, clipping, camera updates, and stable reuse |
| 4. Voxel mesh consumer | Planned | Complete the minimal mesh-drawing API through a real consumer | Intact and carved 8³ cube exported at 512×512 |
| 5. Interactive presentation | Planned | Native surfaces, swapchains, acquire/submit/present, frame lifecycle | Editable cube runs in a Vulkan window |
| 6. Full scene and appearance | Planned | Descriptors, uniforms, sampled images, samplers, shadow passes | Atelier scene, materials, ground, shadows, and brush preview |
| 7. Repeated edits and throughput | Planned | Reusable upload storage, resource retirement, measured batching | Camera flight and repeated carving stay correct with stable resource use |
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

The baseline targets Bend 2.0.37 and 64-bit Linux. The initial Vulkan API level is 1.0.
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

- [ ] Define a packed vertex/index contract shared by the Bend mesher and GLSL shaders.
- [ ] Convert the dense body's exposed faces into indexed quads, retaining face direction and material identity.
- [ ] Start with four vertices and six indices per quad. Share vertices or merge quads in a later optimization.
- [ ] Rebuild and upload the mesh after carving or reset. Camera movement updates camera parameters without rebuilding geometry.
- [ ] Export intact and carved 8³ cube frames at 512×512 through the offscreen graphics path.
- [ ] Check complete exposed-face coverage, absence of interior faces, index bounds, outward winding, and preserved materials.

The existing [geometry module](https://github.com/aivv73/bend-voxel/blob/cdfd92d356229c5de5f4aaddd358f15ec3686dd4/voxel.bend) contains both unit `Face` values and larger `Rectangle` values.
Its dense-body path extracts exposed faces. Its cuboid path emits six rectangles per cuboid.
Before using the cuboid path for the full scene, resolve shared and overlapping boundaries. Those rectangles alone do not establish the exterior of their union.

Completion evidence: formal mesh properties and native rendered output agree on the intact and carved cube's geometry and materials.
Keep the existing renderer as a visual reference. Compare rasterization edge coverage under a stated policy rather than assuming identical floating-point pixel output.
Basic material colors are sufficient here. Production shadows and brush overlays arrive in milestone 6.

## 5. Interactive presentation

Wrapper work:

- [ ] Add a narrow native window-to-surface adapter, initially for Linux/X11, with explicit window and surface lifetimes.
- [ ] Add surface capabilities, formats, present modes, and presentation-support queries.
- [ ] Select graphics and presentation queues from actual support. Handle separate families when the selected device requires them.
- [ ] Add swapchain creation, borrowed swapchain image handles, image views, acquire, present, and recreation.
- [ ] Add binary semaphores and submission wait/signal lists. Track presentation-related resource lifetimes separately from rendering fence completion.
- [ ] Handle suboptimal and out-of-date results as lifecycle outcomes. Handle minimized or zero-sized windows without a busy loop.
- [ ] Keep native events and pointer capture available while Vulkan owns presentation.

Begin with one frame in flight. Add overlap after the ownership and synchronization behavior is verified.
Normal frames use fences and semaphores. Queue-idle waits remain available for simple tools and explicit shutdown paths.

Renderer work: preserve movement, mouse look, carving, reset, and close behavior through the new presentation boundary.
Brush preview can remain absent until milestone 6, but that limitation must be explicit in this checkpoint.

Completion evidence: drive a real native window through camera movement, edits, recreation, and close.
Verify frame ownership, continued input delivery, repeated recreation, and zero remaining wrapper objects after shutdown.

## 6. Full scene and appearance

Wrapper work:

- [ ] Add descriptor-set layouts, pools, allocation, updates, binding, uniform buffers, and sampled-image bindings.
- [ ] Add samplers and depth-image sampling needed for a shadow pass.
- [ ] Support the transitions and dependencies between shadow rendering, sampling, color rendering, and readback or presentation.
- [ ] Protect descriptor contents and referenced resources while submissions use them.

Renderer work:

- [ ] Export the full Atelier scene as a correct exterior mesh, including material boundaries and existing rectangular faces.
- [ ] Port material palette behavior, directional light, sky ambient light, ground, and grid.
- [ ] Restore sun shadows with an explicit image-comparison policy for differences from the existing cached lighting fields.
- [ ] Keep lighting calculations in linear RGB and encode display output once.
- [ ] Restore picking, exact brush selection, tint, and depth-aware brush rings. Keep cell/material identity available independently of merged triangle geometry.

Completion evidence: validate full and carved scenes, several camera poses, unsupported material diagnostics, lighting, shadows, and brush interaction.
Compare world and surface state exactly. Record any intentional appearance differences separately from geometry correctness.

## 7. Repeated edits and throughput

Wrapper work:

- [ ] Add reusable staging storage, subrange uploads, and deferred resource release tied to completion.
- [ ] Support multiple frames in flight without overwriting camera data or buffers still used by earlier frames.
- [ ] Add timestamp queries and clearly scoped diagnostics when the renderer needs attribution.
- [ ] Add optional memory suballocation only after the initial explicit allocation path is stable.

Renderer work:

- [ ] Add chunks and dirty-chunk mesh rebuilds, including neighboring boundaries affected by an edit.
- [ ] Add greedy merging that preserves material, direction, exterior coverage, and shading requirements.
- [ ] Add culling and draw batching when representative workloads justify them.

Completion evidence: repeated carving and reset preserve geometry and reach stable resource use.
Measure complete displayed frames for camera flight and edits. Report meshing, upload, rendering, and presentation costs with their measurement limits.
Tune Bend parallel meshing and GPU frame overlap separately. Retain changes only when representative measurements support them.

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

Start milestone 4 with the packed vertex/index contract in bend-voxel.
Render intact and carved 8³ cubes at 512×512 through the indexed offscreen API.
