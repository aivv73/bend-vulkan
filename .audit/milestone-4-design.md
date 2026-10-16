# Milestone 4 consumer design

Use the unmodified bend-voxel revision `cdfd92d356229c5de5f4aaddd358f15ec3686dd4` as a pinned submodule. The consumer belongs in `examples/voxel/`, with a public `examples/voxel_offscreen.bend` executable. Keep voxel types and policy outside `Vulkan.bend` and `src/`.

## Caller contract

`Mesh.build` returns the owned dense body and packed mesh. `Renderer.replace_mesh` installs geometry after completion and command reset. `Renderer.frame` accepts a camera and returns readback without meshing or uploading. Carve and reset orchestration belongs in the executable. An empty mesh has no buffers or draw.

## Packed contract

Use four vertices and six U32 indices per exposed unit face. Each vertex is 20 bytes. XYZ F32 words occupy bytes 0 through 11. Bytes 12 through 14 hold RGB, and byte 15 holds direction code. Bytes 16 through 19 hold the complete little-endian material ID. The final two attributes use supported `R8G8B8A8_UNORM`. Decode with rounded byte recovery in the vertex shader, then pass metadata flat. Direction codes are -X,+X,-Y,+Y,-Z,+Z in order 0 through 5. The fragment alpha is always one.

Use upstream palette functions for basic colors and preserve unknown positive material IDs with the upstream fallback. Upload exact logical lengths, excluding array padding. Use zero binding offsets and base vertex zero. Keep positions in voxel units. Use outward winding and back-face culling.

## Ownership and projection

The consumer owns attachments, pass, framebuffer, pipeline, command, fence, staging, and mesh allocations. Replacements are synchronous. Observe completion and reset commands before destroying recorded resources. Publish host writes explicitly before vertex/index reads. Read RGBA8 and D32 through staging with explicit barriers.

Use the upstream camera basis and pixel-center convention at 512 by 512. Camera-local `(X,Y,Z)` maps to clip `(420/256*X,-420/256*Y,Z-near,Z)`. D32 is `1-near/Z`. A camera frame changes only pushes and normal frame recording.

## Acceptance contract

Prove pure packing, metadata preservation, quad geometry, counts, and bounded index properties in `LAWS.bend` and `PROOF.bend`. State bounds honestly. Independently enumerate fixture occupancy and exposed neighbors to compare the complete face multiset, including duplicates, directions, and materials. Check decoded packed geometry, not only upstream surfaces. Do not claim pure laws prove GPU behavior or upstream traversal.

Render and export actual intact and carved 8-cubed cube images at 512 by 512. Exercise carve, repeated carve, reset, camera-only frames, empty geometry, adjacent materials, and all six directions. Use the upstream demo metric sphere for the main carved image and name any distinct geometry-dump fixture separately. Verify full U32 metadata on the GPU with high-bit IDs, including 0xffffffff.

Compare native GPU color/depth and diagnostic metadata against an independent geometry oracle and pinned upstream renderer hit functions. Preserve old renderer image exports for visual reference. Define any edge exclusion from reference geometry before looking at differences. Use a one-pixel band at geometric face/clip boundaries, never internal triangle diagonals. Report excluded counts, require no mismatches outside the band, and validate that band pixels still represent valid geometry. Normalize reference depth and use a declared absolute tolerance, at most 2e-5. Shadows and ground are outside the basic-color comparison.

Prove camera-only frames perform no uploads and retain geometry. Reset restores the original mesh and image. Repeated replacement has bounded live resources and scope cleanup reaches zero rows. Extend the existing verifier, shader freshness checks, validation reruns, and relevant sanitizer execution. Keep geometry/packing/reference/export code in Bend. Python may orchestrate existing build and verification tooling.

## Synthesis decision

Three read-only designs were compared. The independent cross-judge selected candidate 1 with 24/25, candidate 2 with 23/25, and candidate 3 with 20/25. The parent agrees. Use candidate 1's supported-format byte encoding and upstream palette. Graft candidate 2's explicit mesh/upload/frame split and independent occupancy oracle. Graft candidate 3's explicit all-material and all-direction GPU coverage.

Reject a new integer vertex format because supported normalized bytes preserve the same information. Reject a generic renderer framework, duplicated palette, cuboid-union mesher, buffer growth system, and performance work because this milestone does not require them. General proofs of upstream extraction are not prerequisites; executable independent geometry checks cover this checkpoint.

## Throughput checkpoint

- Blocking first steps are source tracing, three design sketches, cross-judgment, and baseline verification. All completed before implementation.
- Independent design candidates run in parallel. One implementation owner handles the coupled consumer, shaders, proofs, and verifier.
- Shared mutable files have one writer. The parent owns only this design note and decision log during implementation.
- One implementation owner is the smallest safe decomposition because geometry, packing, shader decoding, and readback share the same contract.

## Verification baseline

`python3 tools/verify.py --sanitize` passed before implementation. The machine uses NVIDIA GeForce GTX 1660, with Khronos and synchronization validation available. The baseline log is `/tmp/bend-m4-baseline.log`.

## Final verification and review

The integrated `python3 tools/verify.py --sanitize` run passed. Its full output is `build/milestone-4-sanitize.log`. The native, validation, and sanitizer voxel logs all contain successful geometry and pixel acceptance results. The exports include intact, carved, reset, empty, and original-renderer images. The combined native readback is checked in at `docs/voxel-intact-carved.png`.

The comment review found no new comments to remove. Independent correctness review found that scanning raw emitted C falsely detected dormant CUDA runtime code. The verifier now checks preprocessed CPU C. The full gate passed after that fix. The separate audit-trail review by `gpt-5.6-sol` found no flags and checked the final full-suite success marker against this run's transcript.

The first pixel comparison rejected clockwise front faces. Counterclockwise front faces passed the same comparison without changing tolerances. The before and after evidence remains in `build/voxel-parent-initial.log` and `build/voxel-parent-winding-fixed.log`.
