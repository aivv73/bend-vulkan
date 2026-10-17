# Milestone 7 workflow

This document records the initial plan. The [results](m7-results.md) and [delivery mapping](m7-stack.json) record completed work.

The completion predicate is a passing full sanitizer and isolated-display suite, exact geometry after repeated boundary edits and resets, bounded live resources, and reproducible complete-frame measurements on the native application.

## Scope

The required changes cover reusable staging and subrange uploads, completion-based retirement, isolated frame resources, dirty chunk rebuilding, and greedy rectangle merging. Timestamp queries provide GPU attribution when supported. Memory suballocation, culling, and additional batching require evidence that they help representative workloads.

The expected work has three coupled implementation units across the wrapper, voxel consumer, and executable verification. At the initial checkpoint, the native singleton presentation lease constrained the design. Existing geometry, production appearance, and native presentation contracts remain acceptance gates.

## Phases

1. Trace wrapper and renderer ownership. Run unchanged proof, geometry, appearance, and validated production checks. Preserve a native baseline binary. The decision trail records the stopped full-baseline run.
2. Compare independent design sketches. Select the smallest model that protects recorded and pending resource references, chunk boundaries, and frame-local mutable data.
3. Build the repeatable measurement and correctness checks before enabling optimizations. Archive baseline measurements with their command lines, device, thread count, and limits.
4. Implement and verify reusable uploads and completion-based retirement.
5. Implement and verify dirty chunk rebuilding and greedy merging against exact geometry identity.
6. Implement and verify frame overlap with independent camera, shadow, command, synchronization, and attachment ownership.
7. Measure complete native frames for camera flight and repeated edits. Compare at least five alternating runs per configuration. Tune CPU meshing and frame overlap separately.
8. Run the complete regression suite. Review the diff and decision trail independently. Update the documented scope to match actual evidence.

## Throughput checkpoint

- Blocking first steps are ownership traces, the unchanged baseline, and the selected design.
- Independent read-only investigations can run together. One implementation owner writes the coupled code in this worktree.
- The implementation has one writer. GPU correctness and measurement runs execute serially. Each frame slot owns its mutable GPU resources.
- The smallest safe decomposition verifies uploads, chunk meshes, and frame overlap in that order. Each unit ends with real execution before the next starts.

## Measurement contract

Count GPU frames whose presentation-resource fences have been observed. Those fences permit resource reuse and may precede completion of the presentation operation. Report event-to-fence latency and handoff throughput with that exact limit. Include edit processing and uploads inside the timed edit region. Retain actual state and image checks so an error or skipped edit cannot count as fast work. Report CPU stage scopes, GPU timestamp support and wrap limits separately. Physical scanout time remains unavailable.

Keep the old and new binaries and run the same workloads. Report the median and range. Treat differences inside observed variation as inconclusive. Do not infer GPU execution gains from CPU thread scaling.
