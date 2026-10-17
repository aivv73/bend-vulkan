# Full milestone 7 review

## Intent

Implement repeated-edit throughput with immutable chunks, reusable staging,
completion-safe lifetime tracking and isolated native frame slots. Preserve
canonical identity and the existing appearance and presentation contracts.
Measure complete native work and state its limits.

## Reviewers

The fixed source capture matches commit `ae91081` in all 171 copied files.
Its full diff SHA256 is
`7cff4894128e7793ae1ca6ad5c95c60adcc76128d85164e98187c53a06cfe10d`.
The user configures all reviewers as `gpt-6.1-sol` at xhigh. These are
independent same-model reviews, with no family-diversity claim.

- Reviewer A reported three findings.
- Reviewer B reported two findings.
- Reviewer C independently reported the same presentation-order failure as B.

## Act on

1. **Publication can retire only part of the old generation.** Reviewer A
   traced a Recording command referencing the old color index buffer. Commit
   collects the old vertex allocation before index retirement rejects that
   recording. Candidate/staging cleanup is then skipped. Root confirmed the
   source path and read the actual reproducer, which reports the old vertex
   gone, the old index live and rows rising34to42. An atomic publication contract
   remains pending. New design sketches compare whole-set validation with the premise
   behind active-recording rejection.
2. **Fixed slot traversal can reverse present dispatch.** Reviewer B traced
   an older Submitted slot being overtaken by a newer recycled slot. Root
   confirmed the call order. Greatest completed revision prevents trace tag
   regression but cannot prevent visual rollback. Submission order must govern
   present calls, including camera-only frames with equal body revision.
3. **Unchanged camera frames repeat generation bookkeeping.** Reviewer A
   found unconditional preparation, run reconstruction and quadratic resident
   searches before every frame. Reuse the installed geometry when the
   authoritative body revision is unchanged and skip commit bookkeeping too.
4. **Bottom-stage intervals are labelled as isolated work durations.**
   Reviewer A found every marker uses BOTTOM_OF_PIPE. Root checked the
   [timestamp dependency scope](https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdWriteTimestamp.html).
   Following work is outside the timestamp's second scope. Correct the marker
   stages and describe inclusive/overlap limits, or relabel the intervals.
5. **Shared and slot-local targets have the same ownership shape.**
   Reviewer B found different destructors for the same type and unused root
   depth/framebuffers in addition to every slot's attachments. Root confirmed
   the allocation flow. Separate shared swapchain resources from local
   attachments and allocate one attachment set per real slot.

## Consider, noted and dismissed

No additional findings have been categorized yet. Earlier upload, generation
and native checkpoint dispositions remain in their own review notes.

## Agreement map

B and C independently traced the same presentation-order failure. A identified
the publication failure and two additional concerns. Root accepted all five
unique findings. Same-model agreement strengthens the call-path evidence; it
adds no model-family diversity. No final approval is claimed. Fixes require
fresh review and real execution.

## Correction checkpoint

The actual device run in `build/m7-ordered-acquisition-run.log` passes
submission-order dispatch, same-revision camera ordering and reversed completion
observation with two pending uniform buffers. The typed shared/local target
sanitizer smoke passes in `build/m7-owned-presentation-run.log`. These focused
checks precede final resize recovery.

Atomic retirement now has a selected design in
[m7-retirement-design.md](m7-retirement-design.md). Implementation and device
regressions remain in progress. Two-slot resize still fails in the controlled
first-resize case. No final source approval or whole-suite pass is claimed.

The first whole-generation correction execution passes in
`build/m7-atomic-publication.log`. Index-only Recording rejection preserves
all installed bytes, handles, counters and rows. The held command submits
before the rebuilt retry succeeds. Mixed changed, removed and reused chunks
retain the exact reused handles. Legacy complete and empty replacement
rejection also preserves the old bytes and cleans candidates. The new native
batch passes its fault checks in `build/m7-atomic-native.log`.

The additional pure residency laws are still being corrected after Bend
compiler errors. These device results do not claim the later source, proof,
commit or final suite has passed. A fixed-capture comment inspection reports
zero deletions and zero MUST KILL findings for the post-review corrections.

## Fresh review round

Round2 uses `build/m7-full-review-r2/source/`, with 175 copied source files.
The complete diff includes the new source files and has SHA256
`db620e034026901e67df5bb303ee29a90bb27eac2f880c23f43a2cb7fcf57453`.
A fresh comment inspection covers33 changed and new files with zero deletions
and zero MUST KILL findings. Root also inspected the later helper-signature
and required-marker delta, which adds no comments.

Reviewers A and B run independently against this fixed capture. C receives
the same consolidated prompt when a slot frees. The prompt includes original
intent, all prior findings, accepted corrections, dismissed barrier claim,
actual device evidence and remaining verification limits. All use the user's
configured `gpt-6.1-sol` at xhigh. No round2 verdict has been adopted yet.

Reviewer A completed round2 with no new findings and no reopening of the five
prior findings. It traced atomic publication, sequence dispatch, unchanged
revision reuse, timestamp limits, target ownership and discard/close recovery.
It verified all 175 captured hashes. This is a source verdict. B and C remain
in progress, and the complete device suite and measurements remain pending.

The capture matches implementation at `c230bff` except two later prose changes
that root inspected. The driver LIMITS entry explicitly distinguishes resource
fence observation from full presentation completion. The presentation contract
now describes Discarding, shared replacement knowledge, four actual fixture
sessions, exact receipt fields and matching resource-fence observation. Neither
delta changes executable behavior.

Reviewer B completed round2. It closes the five prior findings and finds no
concrete reopening of resize recovery. Root accepts two new warnings.

1. **Act on. Analytic extraction duplicates a serial helper.** The only
   `source_faces` caller supplies the six `X.Cuboid.surface` faces. Existing
   `E.parallel_six` preserves that order and checks the same clipping/count
   contract. Reuse it and delete the duplicate. This follows the user's Bend
   parallelism instruction. No performance impact is claimed before measuring.
2. **Act on. The chunk reference follows the returned Body.** The fixture
   passes `C.build` or `C.cut` output Body to `M.build`, so a matching Body and
   geometry mutation can evade the chunk gate. Preserve an independent input,
   compare exact returned Body, and build expected cut state through the pinned
   Body operation on an independent copy. This is a verification gap, not
   observed production corruption.

The owner is correcting these narrow paths. The first full-suite attempt is
superseded for final acceptance, although its completed checks remain recorded.
The final suite and candidate build must use the corrected source. Reviewer C
continues against the fixed R2 capture and may identify further issues.

Reviewer C completed round2 with no new findings and no prior finding reopened.
It confirms the same five corrections and the recovery/close lease path. All
three R2 reviewers close the original five findings. A and C report no new
issue. B alone reports the two accepted chunk warnings. That difference is
coverage, not an explicit disagreement. The two new corrections and their
runtime checks remain open. No final performance or acceptance verdict follows
from this source review.

## Targeted chunk correction review

The fresh review of correction SHA256
`0b2a30d2ff7cbdc0ae501475cc0cb59e08e51d886a48afeb1932290d59f23381`
closes parallel helper reuse and confirms independent dense cloning, sparse
sharing, pinned cut expectations and the material negative control. Root read
the 15-case, one/six-worker determinism and normal proof pass logs at `3bf6303`, and independently
proved the historical checker accepts the same coherent material corruption
that the corrected checker rejects.

The reviewer identifies one remaining **Act on** coverage regression. The
returned Body now passes only through `D.body`, which flattens dense arrays.
An unbalanced array with identical leaves can serialize equal, although the
previous `M.build(returned Body)` rejected it as `InvalidDense`. Preserve the
independent mesh reference and restore balanced-capacity/depth validation on
the returned dense owner. This is a test coverage gap, not observed production
corruption. The owner is applying the minimal test-only correction. Acceptance
remains open until that stronger check runs.

## Native array premise correction

The targeted shape finding is now **Dismissed for the native gate**. Root
accepted it before checking the actual array representation. The attempted
malformed-tree control exits with a native runtime fail-stop before any case
output. Emitted `build/m7-dense-shape.c` explains why. `ANode` lowers to
`blk_node`, which rejects unequal block classes before constructing a parent.
Native arrays are flat power-of-two blocks. `Array.clone` lowers to `blk_copy`.
A native unbalanced tree containing the same 512 leaves cannot reach `D.body`.

For representable native arrays, independent exact side and complete cell
values also establish capacity and depth. The asserted lost topology check
has no executable native counterexample. The owner is confirming the failure
origin and removing the unsupported test-only attempt, restoring verified
`3bf6303`. The failed attempt remains preserved. No interpreted-backend claim
is made. This supersedes the earlier Act on disposition rather than erasing it.

The attempted-patch R4 source reviewer reports no source findings and considers
its explicit shape predicate coherent. It did not execute native code. That
verdict does not establish that the malformed control can run. Actual execution
has priority. The owner confirms the old `D.body` native probe also fail-stops
on the same 512-leaf constructor, recorded in
`build/m7-dense-shape-disposition.json`. The unsupported attempt is removed and
the fixture restored to `3bf6303`. Final verification restarts there.

Two ad-hoc briefs referenced an absent installed agent-style path. The later
reviewer reports falling back to the installed `p3-mode/SKILL.md`. Root located
the actual agent guide at `/home/aivv/Загрузки/p3-stack-main/agents/p3-agent.md`;
future briefs use that path. The review briefs were otherwise self-contained.
This pointer correction changes no source verdict or runtime evidence.

## Legacy consumer collection correction

The complete run at `3bf6303` passed production rendering, independent oracles,
all five corrupt-depth controls, ABI checks and the older geometry-device
consumer. It then failed at `voxel-offscreen`. The reproduced failure is the
exact live-resource assertion after a repeated 396-face replacement.
`build/m7-final-failed-voxel-offscreen.json` records the archived log and hash.
`build/m7-voxel-offscreen-repro.log` contains the actual child output.

Atomic publication deliberately returns the selected owner before later
collection. This caller checked rows before its next frame or readback would
collect. The correction collects in `Acceptance.uploaded` after
`GPU.replace_mesh` returns its replacement Renderer. The exact row assertion,
empty replacement reduction and rollback contracts remain. The verifier also
prints captured child output before rethrowing a failed exit.

The fixed two-file source capture is `build/m7-legacy-collection-r1`.
Its correction SHA256 is
`fa447b2efbb79b7668db2280516347f22ad966e47a1cef74d5e4235cbfa9f857`.
A fresh comment review reports zero findings. A fresh correctness reviewer
traces selected ownership, native reference retention and failure propagation,
then reports no new concrete finding. Both reviews use the configured
`gpt-6.1-sol` model. These are source verdicts. They do not close runtime gates.

The normal proof and repeated atomic/legacy rollback checks pass. Root also
executes actual failing Python children in text and byte modes. Both streams
are forwarded and exit status 7 survives, recorded in
`build/m7-verify-failure-root.log`. Corrected offscreen runtime and the remaining
complete acceptance are still pending at this checkpoint.

The corrected actual offscreen consumer now passes its original geometry,
RGBA8/D32, camera reuse, carve/repeat/reset, empty mesh and exact stable-row
checks with Khronos and synchronization validation. Root read
`build/m7-voxel-offscreen-corrected-run.log` and the pre-commit proof pass in
`build/m7-legacy-collection-commit-proof.log`. This closes the focused defect.
It does not convert the archived failed full run into a pass.

The seven-report bundle under `build/m7-production-pass-3bf6303` has mixed
provenance. The final trail review found that the corrected `ab3f2a1` rerun
had already overwritten the normal and validation reports before the copy.
Their source modification times are 12:02:30Z and 12:05:01Z. The older source
manifest's Acceptance fingerprint does not bind those reports to the old run.
The relabeled manifest preserves every stored byte hash and the original
manifest. This bundle cannot establish coherent historical `3bf6303` report
provenance. The old full log and its failure remain preserved separately.
The final passing `ab3f2a1` archive and correctness acceptance are unaffected.

The final trail review also caught an overbroad sub-millisecond GPU summary.
Main-pass medians in the two edit profile runs are 1.441376 and 1.430944 ms.
Only flight main-pass medians, plus upload and shadow medians in all four runs,
are below 1 ms. The result note and roadmap now report those workload-specific
values. Canonical trail corrections preserve both original mistakes. Fresh
round 3 review confirms both corrections and reports no flags within its
documented scope in `m7-trail-review.md`.
