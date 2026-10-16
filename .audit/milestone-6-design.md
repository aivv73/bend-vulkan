# Milestone 6 implementation design

The selected base is candidate 3, with the smaller descriptor transaction from candidate 2 and post-acquisition frame preparation from candidate 1. The independent judge selected candidate 3 at 21/25, versus 19/25 and 20/25. The parent changed its initial preference after reviewing explicit rectangle bounds and CPU-selected cell identities. These are design scores, not runtime evidence.

## Descriptor boundary

The data shape is a canonical descriptor binding schema plus initialized typed slots. A set retains its layout, pool and current described resources through the existing native dependency graph. A recorded command retains every set it bound until successful command reset or command-pool destruction. Fence completion does not release recorded references. Pending and uncertain commands exclude host memory access through uniform and sampled-image dependency paths, including aliases.

Add checked handles for DescriptorSetLayout, DescriptorPool, DescriptorSet and Sampler. Support uniform-buffer and combined-image-sampler descriptor kinds, arrays and sparse binding numbers. Uniform slices retain explicit U64 offset/range. Offset zero is valid; the range must be positive. Sampled slots retain view, sampler and declared shader-read layout. Ordinary Buffer with uniform usage is the uniform resource.

Use candidate 2's small transaction boundary. Allocate one set per call. Update one destination set with a list of typed writes per call. Free one set per call. Pool reset and destruction invalidate their old set keys only after a successful native operation. Unexpected destructive failures quarantine the pool and preserve conservative dependencies until teardown.

Sampler support uses normalized coordinates, nearest or linear filtering, supported core mip/address/border modes, finite nonnegative ordered LODs, no anisotropy, no comparison and zero LOD bias. Shadow sampling will use nearest and manual comparisons. No dynamic descriptors, descriptor copies, update-after-bind, descriptor indexing or immutable sampler binding schemas are added.

PipelineLayoutCreateInfo gains ordered set layouts beside its existing optional push range. Migrate every caller and actual ABI probe in the same unit. Do not keep a compatibility constructor. Bind uses the active pipeline's layout, compares canonical schemas structurally and requires all declared slots initialized. Every pipeline bind clears descriptor readiness. Draw requires every nonempty declared set position ready. Recorded lifetime edges survive rebinding. Reject unsupported writable-attachment sampling feedback.

Keep all new rows device-owned and represent set pool/layout relationships with role-tagged edges. Pool operations enumerate their member sets from those edges and preflight every external command reference. Keep readiness storage outside the command phase union. Keep reachability allocation-free. Four edges already cover command to set to view to image to memory, as they cover the existing framebuffer path. Name and verify that bound without introducing a generic graph system or blocking unrelated memory.

Create, allocate, update and bind prepare all validation and metadata before Vulkan dispatch. An update constructs the complete replacement slot image and deduplicated content edges, then dispatches once and swaps without allocation. Any earlier failure preserves old contents and protection. Destruction and scope cleanup release commands, sets/pools and described resources in dependency order. Preserve exact Vulkan result bits.

## First unit acceptance

Use public Bend effects to render literal uniform values and a real depth pass sampled into a second color pass. Verify actual readback, arrays, sparse bindings, equivalent schemas, rewritten values after reset and zero final rows. Add executed ABI checks and controlled native probes for readiness, wrong owners/inputs, pool budgets/stale keys, lifecycle phases, deep pending memory protection, failed reset retention, metadata allocation failures, destructive failure quarantine and scope rollback. Integrate these into the existing verifier and sanitizer checks.

The unit gate is generation and shader freshness, `bend PROOF.bend`, new real GPU and boundary evidence, and the complete existing sanitize and native-window suite. The consumer must not depend on this API before that gate passes.

## Source ownership

One delegated implementation owner writes the wrapper unit in the canonical checkout. Parent audit/design files are outside its write scope. The independent design judge reads fixed candidate artifacts and does not write source. Native registry effects stay serial because they mutate one queue and handle graph. Pure meshing parallelism is a later consumer decision.

## Consumer synthesis

Keep candidate 3's rectangle clipping, explicit face metadata, one GPU scene owner, generated uniform fields, integer selected-cell list and static procedural ring triangles. Graft candidate 1's acquisition-ready installation. Keep the existing basic cube shaders and push-camera behavior as regression modes. Graft candidate 2's causal comparison of cached visibility and direct shadow-map visibility. Reject its general boundary sweep and air-paint policy. Arbitrary overlapping non-air cuboids receive a useful unsupported diagnostic in this milestone; the pinned disjoint body and its cuts remain exact.

Candidate 3's complete package was captured before stopping additional read-only consistency exploration. It supplies a design, not execution evidence. The selected contract below resolves the judge's objections. Detailed candidate and judge artifacts remain under `/tmp/bend-vulkan-m6-design/`; the implementation and this contract are the durable record.

### Exterior data and identity

`Body` remains the pinned edit authority. A checked mesh owns canonical `Face` or `Rectangle` coverage plus packed vertex/index arrays. For each supported disjoint cuboid face, subtract the tangential coverage of every non-air box occupying its outward-adjacent cell. Emit positive-area disjoint rectangle fragments with original material and direction. Validate box bounds, disjointness, exact F32 coordinate range and checked allocation/upload sizes. Dense bodies retain the existing extraction semantics. Unknown nonzero material IDs stay occupied and diagnostically magenta.

Use one private 40-byte vertex record for unit faces and rectangles. The first 20 bytes retain position, basic RGB/direction and full material word. The remaining five F32 words carry flat owning-cell anchor XYZ and width/height. Migrate every stride/count reader and proof fixture capacity together. Preserve every existing semantic assertion. Both triangles wind outward with cross-product area width times height. Do not transpose face tangent axes when selecting winding.

CPU and GPU identity use pixel-center ray/plane intersection and the pinned normalized local-coordinate expansion and final clamp. Flat anchor and extents distinguish a rectangle's outer edge from an internal cell boundary. Execute literal cell/material/direction diagnostics at both kinds of boundary. Lighting and silhouette masks cannot excuse identity errors.

The independent acceptance oracle builds occupancy from original body data, never from production face lists. It expands emitted rectangles to oriented unit-face coverage, rejects duplicates/internal faces/material errors and compares every expected face exactly. Inspect actual uploaded bytes as well as source arrays. Check intact Atelier's 803,970 occupied cells, actual cuts, repeated cuts and exact reset. All coordinate and size failures are explicit; no partial or truncated mesh succeeds.

### GPU ownership and frame handoff

`World` owns body, CPU mesh, scene choice, camera, controls, pointer and revisions. `Session` owns one scene GPU resource group beside its presentation target and phase. The offscreen renderer owns an equivalent scene group and its readback target. GPU scene geometry has one owner; do not keep another authoritative copy in World.

The native app defaults to Atelier with `Camera.atelier()`. A cube option preserves existing native regressions. Reset reconstructs the selected original body and keeps the established camera/control behavior. Edits rebuild CPU exterior immediately before the next queued event, preserving current picking.

After acquisition-fence success, install the latest CPU mesh, derive hover and brush from that revision and current viewport/camera, write the frame data and record before another event batch. Thus acquisition-time edits and camera movement cannot mix old geometry with new preview state. Previous presentation completion and command reset still precede resource replacement. The existing single-flight acquire/render/present protocol remains authoritative.

One production recorder owns shadow, background/ground, world shading and rings for native and offscreen targets. Output owners keep attachment transitions, submission, readback or presentation. One static shadow target, sampler, descriptor sets, uniform allocation and ring index buffer survive resize. Target-specific pipelines follow their actual pass and format. No multiple-frame system, render graph or throughput framework is added.

### Uniforms, lighting and brush

Generate the shared GLSL uniform block and Bend packing offsets from one field table in the existing shader tool. Candidate 3's 2,336-byte std140 block includes camera/sun matrices, camera basis, viewport, brush, flags, five linear palette colors, shadow parameters and 125 integer cell slots. The CPU enumerates the fixed 20 cm brush's bounded cell-center candidates through pinned `MetricSphere.contains`. The GPU tints by exact integer membership. Reject invalid radius/count or unsupported coordinates rather than truncate. The consumer coordinate bound keeps centimeter centers exactly representable; it does not constrain the generic wrapper.

Use the pinned Oklch-to-linear palette, sun direction and daylight/sky coefficients. Unknown materials bypass lighting to magenta. Port the authored background gradient and separate non-pickable ground/grid. Compute lighting in linear RGB. Encode once for UNORM output or let the SRGB attachment encode linear output. Preserve existing raw diagnostic byte behavior.

Render a real fixed 512-square D32 shadow pass, then sample it with nine nearest comparisons, receiver-plane slopes and world-space bias. Keep the existing mandatory fragment-stage schema with a no-output shadow fragment shader. Recover an orthonormal sun basis explicitly; undo Z depth scaling as well as XY scale and Y inversion before computing slopes. Compare stored normalized depth and world-space bias with independent equations.

Redraw the shadow map every production frame. Discard prior contents with an explicit dependency from previous fragment sampling to depth attachment access. Transition depth writes from early/late fragment tests to fragment sampling. Order main depth reuse and readback/presentation separately. This removes an unnecessary shadow-cache history flag. Actual repeated-frame synchronization validation is required.

Generate three 32-segment rings from one static indexed triangle buffer and frame brush data. Clip to near, expand in screen pixels and test the reference stroke distance. Interpolate reciprocal eye depth and depth-test after voxels without depth writes. The presentation ground remains outside voxel picking and ring occlusion semantics. Verify visible front arcs and hidden back arcs independently.

### Comparison and verification

Exact world/material/exterior/selected-cell state has no image tolerance. Keep old cube readback and edge rules. Stable new lighting compares to independent linear equations and direct depth-map PCF with named numerical tolerances. Compare cached-reference differences through independently computed cached and direct visibility; a cache-tile-edge mask alone is insufficient. Report raster edges, shadow taps and ring contact differences separately. Never hide missing geometry or wrong identities in appearance exclusions.

The judge's remaining execution obligations are acquisition-time consistency, correct sun-basis units, literal identity at boundaries, real rendered-and-sampled depth, deepest descriptor memory paths and aliases, exact occupancy/upload checks, repeated synchronization and actual native interaction/captures. Each unit must pass before its dependent unit. `milestone-6-contract.md` remains the completion predicate.

### Effective reference shadow resolution

Native execution of `ShadowMap.build` confirms that pinned Atelier uses 512 square. `Shadow.depth()` is the base setting of 7, but `ShadowMap.build` selects depth 9 for an extent above 32. Atelier's extent is 440. The earlier inference from the base setting alone was wrong. The executed probe is `/tmp/bend-vulkan-m6-reference-lighting/build/resolution-runtime.log`.

Compare the original reference's cached 512-square visibility with its direct 512-square depth visibility, then compare direct production visibility against actual 512-square GPU depth readback. This separates cache approximation, projection arithmetic and rasterization. The reference artifact also contains an explicit 128-square experiment, which is not the actual default Atelier configuration. Predicted visibility differences can explain appearance changes; they cannot excuse missing geometry or incorrect cell/material identity.
