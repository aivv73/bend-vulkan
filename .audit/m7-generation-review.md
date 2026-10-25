# GPU generation review

The snapshot is `e080779` against `9982444`. Comment inspection found no deletions or MUST KILL flags. Independent correctness review found no concrete blocker.

The reviewer traced complete CPU chunk and staging ownership through partial preparation failure, candidate cleanup after recording failure, exact key/version reuse, retirement of replaced residents, local color ranges and greedy shadow draws. Read-only parsing of both existing 15-case chunk artifacts confirmed valid local ranges and exact reconstructed canonical order.

The earlier missing-barrier concern remains dismissed. `Scene.record` calls `GPU.publish` before both passes. Its chunk barrier covers host and transfer writes before vertex and index reads. Caller-owned commands and fences plus retained-plan cleanup address the earlier post-prepare ownership gap.

The normal and sanitized generation logs pass. The corrected installer passes under ASan, UBSan and synchronization validation with four handled begin/mid-copy failures. The initial ordinary installer log records a missing-header compilation failure. It is not a passing run. Current source contains the header. The final complete suite must rebuild the final artifact.

The preparation fault checks cover one chunk's four allocations and uploads. They do not directly exercise rollback after an earlier chunk succeeds or mixed reused/changed residents. Generation-level injected end, submit, wait and reset failures remain coverage gaps. Native lifetime probes cover those states separately. Logical array contents are asserted; complete backing capacity and padding preservation are supported by source inspection rather than explicit assertions.

The earlier production run passes the unchanged normal/validation appearance oracles and original-Body shadow causality checks, including all five corrupt-depth negative controls. It predates the installer signature cleanup. It does not prove byte-identical shaded output against milestone 6. Root compared 195 archived/current RGBA captures in `build/m7-offscreen-baseline-diff.json`. Of these, 171 are exact. The 24 differing shaded captures have a maximum channel difference of four. Intact, carved and reset each differ at five pixels; portrait differs at 92 pixels. Canonical metadata and identity outputs remain exact. Native static parity is still pending.

Evidence is in `build/m7-generation-gate.log`, `build/m7-generation-sanitize-gate.log`, `build/m7-generation-proof.log`, `build/m7-installation-gate.log`, `build/m7-installation-sanitize-gate.log`, `build/m7-chunk-production.log` and `build/milestone-6-production/shadow-causality/results.json`.

The independent review is T3 task `m7-generation-correctness-review-r1`, configured as `gpt-6.1-sol` by the user's model overrides. It inspected committed source and saved artifacts without builds, device workloads or edits. Native overlap and interactive integration are outside this checkpoint verdict.

## Later integration finding

The full review at `ae91081` reopens publication atomicity. A separate command
left Recording against only the old color index buffer causes commit to
collect the old vertex before rejecting the index retirement. The actual
device reproducer reports rows rising from 34 to 42 in
`build/m7-publication-repro-run.log`. Candidate and staging cleanup are skipped
on that path. The focused preparation and recording-failure verdict below
does not cover this later publication rejection. A coherent retirement-set
boundary and fresh fault verification remain required.
