# Coherent retirement and publication

Existing callers keep their installed `Scene.Group` and attempt installation
through `Scene.install_chunks`. Success returns the replacement and source set.
A clean rejection leaves the retained group usable; callers rebuild candidate
arrays before retry. This preserves the current Action API. Preparation still
returns affine arrays and reusable staging outside its status value.

## Selected shape

Use one `Device.retire_buffers` effect over the complete list of dedicated
buffer/memory pairs. Parse the input once into temporary storage, validate
every member, then seal all members without allocation or dispatch. The native
IO loop keeps registry pointers stable during this operation. Empty input,
identical duplicates and repeated retirement of live rows are supported.
Any rejected member or scratch allocation changes no retirement flags.

Whole-geometry release and `G.commit` each submit one complete obsolete set.
Exact retained chunk keys and versions are excluded. Delete the singleton
native effect and migrate its callers. Singleton staging retirement uses the
same operation. Collection runs at a later lifecycle boundary.

The synchronous installer completes and resets its upload command, releases
temporary staging, then atomically seals obsolete geometry. Rejection cleans
every fresh allocation in `Plan.created` and preserves diagnostics. Success
returns the replacement immediately, with no fallible cleanup before the
owner is selected. Frame staging remains reusable. Legacy mesh upload needs
the same cleanup after rejected old-geometry retirement.

## Alternatives and synthesis

Three independent sketches compared atomic retirement with a broader policy
where existing recorded references authorize first submission after sealing.
Both can retain memory safely. The broader policy changes submit guards,
already-bound draw semantics and partial-disposal outcomes. Removing only the
active Recording guard makes successful staging growth invalidate its upload
at submission. That is not a complete alternative.

The fresh judge selected sketch 2, with sketch 1's late allocation-alias probe
and sketch 3's legacy-upload coverage. It rejected the proposed broader
installer owner-result API because existing callers retain Data handles and
rebuild candidate arrays. No tickets, residual retry queues or publication
state variants are needed. Device loss or repeated reset/cleanup uncertainty
ends the resource scope.

## Verification contract

The original actual-device repro reports an invalid old vertex, a live old
index and rows rising from 34 to 42. The corrected regression must reject
atomically, preserve every old handle and byte, clean candidates and staging,
then permit the held command to finish and a replacement retry to succeed.
Late bad-pair/alias and scratch-allocation failures must preserve earlier
members. Mixed reused/changed residents, legacy upload and existing staging,
pending/completed/failed-reset lifetime checks remain required.

The sketches and judge are preserved in `build/m7-retirement-design-1.md`
through `-3.md` and `build/m7-retirement-design-judge.md`. All four used the
user-configured `gpt-6.1-sol`. They were independent read-only inspections.
This design is selected; implementation and fault gates remain pending.

## Execution checkpoint

The native batch passes ASan/UBSan fault checks in
`build/m7-atomic-native.log`. A late bad pair, actual allocation alias and both
scratch-growth failures leave earlier allocations unsealed. Empty sets,
duplicates, live idempotence and exact cleanup also pass, alongside the prior
pending, failed-reset and sealed-command tests.

The final selection-helper rebuild passes both device fixtures in
`build/m7-generation_recording.log` and `build/m7-legacy_retirement.log`.
Rejection preserves installed bytes, handles, counters and rows. The held
command then submits before a rebuilt candidate succeeds. Mixed changed,
removed and retained chunks preserve the reused resident's exact handles.
Legacy complete and empty replacement rejection preserves the old geometry
and cleans fresh buffers. `build/m7-atomic-retirement-proof.log` passes the
normal `bend PROOF.bend` check for the concrete selection laws.

The installer API remains unchanged. Whole-generation commit returns the
selected owner before later collection. Final full-suite acceptance and fresh
code review remain pending.
