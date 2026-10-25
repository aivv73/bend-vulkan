# Milestone 7 selected design

Candidate 1 is the base. Its canonical color and picking primitives preserve the existing F32 ownership rules. Greedy rectangles feed the production shadow pass. The independent design judge also selected candidate 1, with scores of 23, 22, and 14 out of 25. The judge report is in `m7-design-judge.md`.

## Grafts and rejected alternatives

Use candidate 2's analytic cuboid extraction and sparse ownership. Cuboid source bounds already form disjoint adaptive regions. Start with those regions as chunks and refine only where edits require it. Match unchanged regions by exact source tuples, retain canonical source order, and dirty neighboring surface owners when blockers change. Large cuboids must stay analytic rectangles. Dense bodies use bounded spatial chunks and one-cell neighbor queries. Neither path may voxelize a large cuboid into a fixed grid.

Use candidate 3's scheduler discipline. Advance every slot, fill available slots, then wait. Timestamp reads retain availability and reject ambiguous wrap intervals.

Keep shared immutable GPU chunk generations. Each frame owns staging, commands, synchronization, uniforms, descriptors, depth, shadow resources, framebuffers, and query storage. A completed acquisition selects one coherent geometry and appearance snapshot.

Reject frame replicas and mutable span arenas initially. They duplicate unchanged geometry and introduce allocation packing before measurements justify it. Reject changed shader cell arithmetic and merged canonical color primitives. Exact identity is a requirement.

## Native lifetime contract

Replace singleton submission and acquisition assumptions together. All active commands participate in host exclusion and idle completion. Commands retain the exact acquisition generation, and fence observations update only the associated lease. Timeouts retain ownership. Uncertain submissions quarantine new work until recovery. Device loss never counts as successful completion.

Expose typed acquisition ownership where ambiguity requires it. Keep completion receipts internal where the existing dependency graph already proves safe retirement. Buffer retirement seals new use and retains the buffer and its dedicated allocation until every recorded reference disappears. Those references can disappear only after proven completion and successful command reset or pool destruction. This provides generation safety without using a reusable fence key as a retirement token. Real pending, failed-reset, fence-reuse, and uncertain-submission checks must prove this property.

Source-subrange writes preserve the affine array on every outcome. Validate source and destination ranges at the native boundary. Reuse explicit staging allocations and existing buffer-copy regions. Allocate and prepare replacement chunks before publishing the new revision. Failure must preserve installed geometry.

## Verification contract

Preserve the existing full geometry and production appearance gates. Add optimized semantic checks alongside historical source-order and quad-count checks. Prove every exposed side appears once with its full material and direction. Exercise dirty boundaries, no-op cuts, queued edits, reset, empty geometry, and deterministic parallel builds. Greedy shadow geometry needs actual depth and causal-shadow evidence.

Prove two native submissions can remain pending before either fence is observed. Verify independent camera and shadow data, exact lease isolation, bounded resource and metadata use, and zero-row cleanup. Extend the native failure probes and generated bindings.

Run the native measurement driver with at least five alternating pairs. Tune CPU thread count at fixed frame count, then frame count at fixed thread count. Keep optimizations only when the representative results support them. Report unavailable scopes and instrumentation limits. Optional memory suballocation, culling, and extra draw batching remain conditional on evidence.
