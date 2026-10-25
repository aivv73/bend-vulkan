# Pure chunk review

The snapshot is `0eab008` against `c3f612d`. Comment inspection found no deletions or reshape flags. Root and an independent `gpt-6.1-sol` reviewer inspected the chunk model, dirty selection, canonical ordering, greedy coverage and executable checks.

The independent reviewer found no concrete correctness or structural blockers. Its read-only checks against both recorded dumps passed all 15 fixtures. The one-thread and six-thread outputs are byte-identical. Additional inspection confirmed that local faces appear exactly once in canonical draw runs and retain material, direction, extent and owner bounds.

The review covered source-domain metadata refresh when packed faces stay equal, changed blocker dependencies, empty chunk removal and parallel work reordering. The color stream preserves original face records and ordering. The signed corner oracle checks merged coverage without expanding large rectangles.

Reset, empty-after-edit and equal-face metadata-refresh sequences lack dedicated fixtures in this snapshot. Inspection found no reachable defect in those paths. GPU integration and the final repeated-edit acceptance run remain outside this verdict.

The proof log reports `ALL PROOFS CHECK`. The reviewer ran no compiler, GPU or window workload. T3 task `m7-chunks-correctness-review-r1` records the full result.

## Later full-review findings

Full review R2 found two additional concerns. The earlier checkpoint verdict
remains bounded and does not waive them. Root accepts both.

- Replace serial `source_faces` with existing `E.parallel_six` for the six
  analytic source faces. Delete the duplicate helper. No measured impact is
  claimed yet.
- Preserve an independent authoritative Body in the pure chunk fixture.
  Building a reference from the returned Body can hide matching Body and mesh
  corruption. Compare exact returned state and derive expected cut state from
  the pinned operation on an independent input.

The source correction and stronger gate are in progress. The early full-suite
attempt is superseded for final acceptance. A new ordinary candidate and final
suite must use the corrected source.

The independent-input and parallel-helper corrections pass at `3bf6303`.
All 15 cases and one/six-worker byte identity pass, and root runs both historical/current
checkers on the same hashed material corruption control. The historical gate
accepts it and the corrected gate rejects it.

A later targeted reviewer proposed an additional topology warning. Its native
counterexample is dismissed after actual execution and runtime source
inspection. `ANode` construction rejects unequal block classes, so an
unbalanced native array with the same 512 leaves cannot reach serialization.
Exact independent side and complete cell values establish capacity/depth for
representable arrays. The attempted extra control fail-stops and is removed;
its failed evidence remains separate. See the full review's native array
premise correction. No interpreted-backend conclusion follows.
