# Milestone 6 acceptance contract

The user requested all of milestone 6 in `docs/roadmap.md`. The implementation must preserve the milestone 0 through 5 acceptance paths.

## Completion predicate

The public wrapper creates, updates, binds and destroys descriptor layouts, pools, sets and samplers. Uniform buffers and sampled depth images participate in the existing ownership graph. Recorded and pending commands prevent unsafe descriptor mutation, destruction and host writes through referenced memory. Invalid inputs fail before Vulkan dispatch. Partial native failures release their metadata and native resources.

The renderer displays the full pinned Atelier body as an exterior mesh. Rectangular faces retain their extents, material and direction. Interior faces and duplicate coverage do not enter the output. An independent occupancy or plane-coverage comparison verifies intact, carved and reset geometry exactly. Rendering preserves cell identity independently of triangle size. The pinned scene and its cuts use disjoint cuboids. Arbitrary overlapping cuboids may be rejected with a diagnostic instead of requiring a general union normalizer.

The scene has the pinned material palette, directional sun, sky ambient light, ground and grid. A real depth shadow pass feeds sampled lighting. Calculations use linear RGB and encode the display once. The comparison policy separates exact world and geometry state from documented differences caused by rasterization and the reference renderer's cached lighting fields.

The native application supports pointer picking, exact metric brush selection, selected-cell tint and depth-aware brush rings. Pointer motion, captured look, camera flight, queued edits, reset, resize, suspension and close remain usable. Evidence includes the real native product and reproducible acceptance commands.

Generation freshness, `bend PROOF.bend`, old acceptance checks, new real GPU readback, native boundary probes, Khronos and synchronization validation when available, and relevant ASan and UBSan runs must pass. Unavailable checks are recorded as unavailable, never as passed.

## Designed workflow

1. Trace the current wrapper, mesh, reference appearance and native frame flow. Capture the pre-change complete verification baseline.
2. Compare independent architecture sketches. Select the descriptor ownership model, exterior extraction and renderer resource shape before writing implementation logic.
3. Add the descriptor and sampling boundary with native readback, failure and lifetime checks. Verify this unit before the scene depends on it.
4. Add full exterior extraction and exact geometry checks. Verify intact, carved, reset and touching material coverage. Verify the explicit policy for overlapping input.
5. Add lighting, the shadow pass and brush preview through the chosen renderer state. Verify several poses and native interaction.
6. Run the complete regression and native-window suite. Independently inspect the actual output and audit the implementation and evidence.
7. Deliver ordered verified commits and a linked pull request. Record remaining support boundaries and intentional appearance differences.

## Throughput checkpoint

- Blocking first steps. The existing complete suite and architecture decision precede source changes.
- Independent workstreams. Read-only exploration and design use separate reports. The baseline runs beside them. Implementation follows the coupled API and consumer dependency order.
- Shared mutable state. One implementation owner writes the canonical checkout. Design candidates write separate files under `/tmp/bend-vulkan-m6-design`. Parent review does not edit source while an owner is active.
- Smallest safe decomposition. Wrapper descriptors and their verification form the first unit. Exterior geometry is the second. Appearance and native interaction form the third. Shared generated API files and the renderer state prevent concurrent source owners in this checkout.

## Rigor and limits

Native handle lifetime changes need high rigor because incorrect ownership can become GPU use-after-free. Geometry uses exact comparisons. Appearance uses named tolerances and explicit exclusions, with no geometry exclusions hidden inside color tolerances. This task makes no performance claim and does not introduce the milestone 7 multiple-frame or chunk systems.

The baseline command is `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display`. Its log is `build/milestone-6-baseline.log`.

## Implementation throughput checkpoint

- Blocking first steps. The complete baseline passed and the architecture is selected. Consumer source integration waits for the descriptor unit gate.
- Independent workstreams. One source owner implements descriptors in the checkout. Another prepares pure geometry and its independent oracle under `/tmp/bend-vulkan-m6-geometry`, using only pinned world types. The parent captures and reviews reference evidence.
- Shared mutable state. Only the descriptor owner writes implementation source in the checkout. The geometry worker cannot modify it. Parent-owned audit files remain separate. The artifact is integrated by a later source owner after review.
- Smallest safe decomposition. Pure geometry has no descriptor dependency, so scratch preparation can proceed now. Native API integration and final renderer state still follow verified units with one canonical writer.
