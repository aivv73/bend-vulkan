# Measurement driver review

One independent `gpt-6.1-sol` reviewer inspected `tools/measure_m7.py` and the actual baseline smoke artifacts. Root read the identified paths and accepted three corrections before comparative measurements.

1. Missing completion tags made `all([])` true. Revision installation followed by an older frame's completion could satisfy an overlapping edit measurement. Legacy fallback needs verified single-frame provenance. Tagged completion must identify the requested revision exactly.
2. Tagged completion on the first installed record was excluded. The search needs to include that record and compare its frame counter with the pre-edit counter.
3. Each side's screenshots were compared only with its own originals. A different scene or wrong cut could pass. Corresponding static fixtures and geometry/view state need a cross-side gate before a pair is eligible for performance summaries. Flight endpoints depend on movement duration and cannot be compared as identical poses.

The current row predicate establishes a bounded observed range and no higher second-half maximum. It does not prove every rising tail is stable. The four baseline smoke sessions had fixed reset rows of 56 and no native allocation counters. They establish no metadata-allocation plateau.

The smoke report, native executable hashes, raw state counts and 26 saved image hashes agree. All four runs used the unchanged baseline. Validation was disabled, stage timings were unavailable, and no limiter profile or logging-delay bound was collected. These runs establish driver function only.

The original review is T3 task `m7-measurement-correctness-review-r1`. A fresh worker prepares the correction in isolated scratch storage as `m7-measurement-validity-fix-r2`. The active implementation owner remains the only source writer.

Root reviewed the completed patch and independently ran all 22 focused behavioral checks successfully. The original script fails the same suite. These checks use scripted traces and stubbed inputs to test driver decisions. They establish no GPU behavior. The patch, regression script and before/after results are archived in `build/milestone-7-driver-correction/`.

Candidate edits now require exact completion revision tags. Legacy untagged behavior is restricted to this run's preserved baseline path, binary hash, manifest and source commit. Other legacy baseline builds require new provenance work. Static paired image and state mismatches exclude a pair from reported metrics. Resource assertions describe the observed range and half-window maxima without claiming full tail stability.

Native smoke remains pending against the new window. The implementation owner was authorized to apply the prepared correction before comparative runs. Root also verified the ordinary compiler command using an isolated same-version build. Bend 2.0.37 invoked Clang with `-std=c11 -O3`. Actual baseline command provenance and the observed compiler arguments are archived under `build/milestone-7-baseline-build-provenance.json` and `build/milestone-7-compiler-argv.jsonl`.

The scratch checks now have a portable repository runner at `tools/check_measurement.py`. Its original 22 cases preserve the same 52 assertions. The portable preparation passed from another working directory and from a checkout path containing spaces. The original driver produced the same 40 failure cases with zero test errors. Root then inspected the applied runner and ran the expanded 25-case suite successfully. The three additional cases check literal CPU U64 limbs, GPU F32 nanoseconds and timestamp capabilities, including invalid numeric encodings. The 40-case failure comparison applies to the original 22 tests. These are pure driver checks, separate from native execution.

Integration review found two producer issues before measurements. A failed query reset could leave completed old results visible through the slot's pool. The consumer now carries a per-frame query view and disables that view after reset failure. The actual old-completed-query and reset-allocation-failure probe passed normally and under ASan, UBSan and synchronization validation in `build/m7-timing-reset-sanitize.log`. A newer completed revision could also be overwritten by an older slot before the next STATE record. The current draft preserves the greatest completed body revision, reserves the unavailable sentinel and rejects revision exhaustion. Its expanded device regression remains pending at this checkpoint.

Stage names describe producer scopes. CPU edit-event processing and buffer preparation can include deferred pure Bend work. Without an explicit forcing or profiling argument, neither scope establishes an isolated mesher cost. GPU upload, shadow and main durations use separate timestamp pairs. Presentation-call CPU duration and presentation-fence completion also remain distinct. Stage samples across a complete run include warmup and settling unless the report explicitly filters them.

The committed frame correction uses TOP-to-BOTTOM timestamp windows. These
windows include prior completion and can overlap later work. They are not
exclusive pass costs and cannot be added to CPU scopes. A frame counter records
completed rendering and observation of a matching presentation-resource fence.
It does not establish physical scanout or full presentation completion.

At `ab3f2a1`, the ordinary candidate rebuilt to the same executable hash as
`3bf6303`. The actual compiler arguments were observed during this candidate
build and include C11, `-O3`, X11 and dynamic loading. Evidence is
`build/m7-candidate-compiler-argv-ab3f2a1.json`. The original baseline compiler
invocation was not intercepted. The separate same-version probe remains its
flag evidence. Native candidate comparisons and the limiter profile have not
run at this checkpoint. The complete corrected acceptance run is active.
