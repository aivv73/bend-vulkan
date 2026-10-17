# Initial design judgment

This note records inspection of baseline `928bee9e677983c063811e0540f8783d86467a83` before milestone 7. Source citations are pinned to that revision and its dependencies. Current contracts are in the [API reference](../docs/api.md) and [voxel reference](../docs/voxel.md). Completion terminology is qualified in the [measurement review](m7-measurement-review.md).

Recommend **candidate 1 as the base**, grafting candidate 2's sparse cuboid ownership and candidate 3's explicit scheduling and query-result details. None should proceed unchanged.

Scores assess design completeness; no implementation or performance result is established.

| Rubric item | Candidate 1 | Candidate 2 | Candidate 3 |
|---|---:|---:|---:|
| Exact geometry/shading identity, chunk boundaries, full U32 material | 4 | 3 | 1 |
| Completion ownership, recorded references, pending work, retries, cleanup | 5 | 5 | 4 |
| Native completed-frame measurements; separate baseline/thread/slot comparisons | 5 | 5 | 4 |
| Small voxel-independent public API; authoritative generated bindings | 5 | 4 | 2 |
| Incremental delivery with meaningful device/sanitizer gates | 4 | 4 | 3 |
| **Total /25** | **23** | **22** | **14** |

**Candidate 1** provides the strongest identity strategy: retain canonical, unsplit color and picking primitives, including original anchors, extents and draw order; apply greedy merging to production shadow geometry. This addresses the actual contract more directly than changing ownership arithmetic. The shader's normalization, expansion, floor and clamp are observable behavior, backed by the [width-41 witness](https://github.com/aivv73/bend-vulkan/blob/928bee9e677983c063811e0540f8783d86467a83/tests/appearance_cases.bend#L79) and [literal raster-fringe assertions](https://github.com/aivv73/bend-vulkan/blob/928bee9e677983c063811e0540f8783d86467a83/tools/production_oracle.py#L125).

Its principal gap is large-cuboid scaling. Fixed 32-cell ownership, populated chunks and plane masks lack a bounded construction for huge valid cuboids. Analytic face extraction avoids volume voxelization, but fixed surface tiling can still explode. Resolve this before implementation.

Shadow merging also needs actual GPU evidence: equal exterior coverage does not prove identical rasterization or shadow depth. Describe greedy scope honestly. Shadow triangles decrease. Canonical color triangles remain.

**Candidate 2** handles large cuboids best. Sparse macro-chunks, local refinement, analytic face clipping and differently sized neighbors provide a concrete alternative to expanding large solids into tiles. Its lifetime model also correctly distinguishes submission epochs from reusable fences and retains resources through recorded references.

Its blocking uncertainty is `RenderRect{coverage,identity}`. Keeping original metadata can preserve arithmetic when clipping one canonical domain; one flat identity record does not generally reproduce several distinct canonical domains. For example, retaining one original unit face's extent clamps every fragment to that face's cell. Changing the extent requires a separate equivalence argument. Clipping and retriangulation can also change coverage at raster fringes, independently of metadata.

"Enable classes after exact checks" is a gate, not yet a constructive merging rule. Falling back everywhere would preserve correctness while failing the promised meaningful greedy reductions. Deterministic chunk traversal likewise needs to preserve canonical hit/draw tie behavior, not merely produce repeatable new ordering.

**Candidate 3** offers useful scheduling detail but requires the largest revision. Fixed 16³ occupancy tiles across the original occupied domain imply potentially enormous initialization/reset work for large cuboids; limiting later gathers to dirty tiles does not solve that.

Its proposed extent-independent shader recovery changes the pinned ownership calculation. A newly specified integer boundary rule is insufficient unless it reproduces canonical F32 results, including normalization and fringe clamping. Updating CPU picking to the same new rule establishes agreement between implementations, not equivalence to existing behavior.

Frame replicas are viable in principle, but automatic span packing introduces buffer suballocation, fragmentation and repacking before measurements justify them. The generic `Resource` destruction API, ticket status/release surface and explicit optional submission lease also broaden the public wrapper unnecessarily.

Explicit grafts:

- **From 2 into 1:** sparse cuboid macro-chunks with local refinement, analytic rectangle extraction and cross-level neighbor ownership. Keep temporary cell masks bounded. Preserve candidate 1's remote canonical-domain invalidation and global source ordering.
- **From 3 into 1:** service every slot and fill free slots before waiting; request nonblocking timestamp results with availability, retaining partial results on `VK_NOT_READY`; use CPU elapsed bounds to reject ambiguous timestamp wraps.
- **Retain from 1:** preallocated submission metadata, sealing against future recording/submission, canonical color/picking domains, and acquisition-time immutable snapshots.
- **Reject initially:** candidate 2's merged color path without a defined equivalence rule; candidate 3's shader arithmetic replacement, fixed cuboid voxelization, automatic arenas and generalized destruction API.

The native ownership requirements are substantive: [completion retains recording references](https://github.com/aivv73/bend-vulkan/blob/928bee9e677983c063811e0540f8783d86467a83/src/native.c#L249), while current idle and memory-busy checks inspect only one active command. All three identify this coupled change. Preserve candidate 1's explicit device-level quarantine during uncertain submission recovery.

For delivery, require genuine two-pending-submission evidence, distinct camera/shadow readbacks, failed-reset retention, OOM retries, stale lease/fence rejection and bounded metadata. Keep the full sanitizer/isolated-display suite and production shadow negative controls mandatory.

Candidates 1 and 2 explicitly require equivalent baseline instrumentation. Candidate 3 needs that addition: preserving an old binary alone does not provide comparable completion/stage probes. Compare threads at fixed slot count and slots at fixed thread count, with five alternating runs, state/image validation and instrumentation overhead recorded.

Read-only inspection completed; no writes, git mutations, delegates, acceptance runs or benchmarks.
