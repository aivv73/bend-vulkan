# Milestone 7 evidence

The complete acceptance command passed at source `ab3f2a1102db132ab60ec26afd69a7784b1e1c67`.

```sh
env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display
```

The [acceptance record](m7-acceptance.json) identifies the source, exit status, component outcomes and artifact hashes. The [complete log](m7-verification.log) preserves the actual command progression. The [native capture](m7-native-atelier.png) shows the tested default Atelier window.

## Correctness

- Exact geometry checks include independent original Body state, pinned cuts, dirty boundaries, canonical order and byte-identical output with one and six workers. A coherent material mutation fails the negative control.
- Actual device checks cover reusable staging, atomic whole-set retirement, failed-publication rollback, recorded references, two pending submissions and independent readbacks.
- Acquisition checks cover every byte of the 2,336-byte appearance input, distinct camera and shadow data, submission order independent of body revision, reversed completion observation and obsolete-lease cleanup.
- Native windows pass with shared and distinct queue pairs 0/0 and 0/2. Checks include edits, reset, flight, resize, suspension, remap, close and ordinary quiet launch. Traced shutdown checks reach zero rows.
- Khronos and synchronization validation and actual ASan/UBSan execution pass on NVIDIA GeForce GTX 1660 under Linux/X11.

The [195 archived/current offscreen RGBA comparisons](m7-appearance-diff.json) contain 171 exact captures. The remaining 24 shaded captures differ by at most four channel units. Exact geometry, identity and current shadow-causality gates pass. Shaded output is not byte-identical to the old implementation. The native old/new measurement driver retains a stricter exact static RGB eligibility rule. The [production manifest](m7-production-source-manifest.json) preserves source and capture hashes from the passing full run.

## Performance

The overall production-performance verdict is inconclusive. The [old/new comparison](m7-old-new.json) has no eligible timing pairs. All 20 native processes exited zero and all 160 edit actions completed, including warmup. All ten timing pairs were excluded by exact static RGB mismatches. No implementation speedup is established.

The independent [instrumented profile](m7-profile.json) passed four runs. Whole-run application CPU averages range from 2.18 to 2.55 cores, and the sampled observer process averages range from 0.08 to 0.10 cores. Producer record/submit medians are about 20.5 ms. The two flight runs have main-pass inclusive GPU medians of 0.601 and 0.624 ms. The two edit runs have main-pass medians of 1.431 and 1.441 ms. Upload and shadow medians are below 1 ms in all four runs. These observations point toward host recording and submission cost. They do not isolate individual renderer costs or account for every observer subprocess.

The profile includes polling, warmup and settling. CPU producer scopes can realize deferred Bend work. GPU TOP-to-BOTTOM windows can overlap and include preceding work. Device-wide GPU utilization includes the desktop. No call stacks or instrumentation-overhead estimate are available. Profile samples are excluded from comparative timings.

Flight comparisons share scripted input duration. Time-driven camera poses can differ, so they do not establish identical per-frame GPU work. Throughput counts observed matching presentation-resource fences, which permit resource reuse and may precede completion of presentation. Physical scanout is unmeasured. Edit latency includes event dispatch through observation of a completed frame tagged with the requested revision. Trace receipt, polling and scheduling delay remain included.

The [build record](m7-builds.json) identifies both ordinary executables, compiler evidence and source revisions. A [diagnostic of the first old/new pair](m7-native-image-diff.json) independently finds four changed RGB pixels in each static image, with a maximum channel difference of four. The [complete static-image report](m7-native-static-parity.json) records the same result for all 90 capture pairs. Geometry and view signatures match. These diagnostics change no eligibility rule and establish no cause for the difference.

The [CPU comparison](m7-cpu-1-6.json) holds the executable and one frame slot fixed. All 20 processes exit zero, all 160 edit actions complete and all output assertions pass. Each workload has five eligible alternating pairs. The table gives the median and range across runs. Cut and reset entries summarize each run's median of six measured actions; warmup actions are excluded from those timings.

| Observed metric | One worker | Six workers |
| --- | --- | --- |
| Presentation-resource handoffs per second | 42.44, range 42.36 to 42.86 | 41.32, range 41.05 to 43.16 |
| Cut latency in ms | 1,207.5, range 1,202.0 to 1,231.4 | 1,669.2, range 1,645.3 to 1,682.5 |
| Reset latency in ms | 9,483.1, range 9,373.3 to 9,537.9 | 4,034.1, range 3,998.1 to 4,044.3 |

Flight ranges overlap. One worker has lower observed cut latency, while six workers have lower reset latency. This is a tradeoff for the traced configuration. It establishes no universal worker winner, implementation speedup or isolated CPU meshing speedup. The separate profile covers six workers and two slots, so it cannot establish the exact limiter for every CPU configuration. Trace overhead remains unmeasured. No production default changes follow from this sweep.

The [slot comparison](m7-slots-1-2.json) holds the executable and six workers fixed. All 20 processes exit zero, all 160 edit actions complete and all output assertions pass. Each workload has five eligible alternating pairs. The table uses the same per-run summary policy as the CPU comparison.

| Observed metric | One slot | Two slots |
| --- | --- | --- |
| Presentation-resource handoffs per second | 41.80, range 41.48 to 42.13 | 43.81, range 43.20 to 44.39 |
| Cut latency in ms | 1,666.1, range 1,638.9 to 1,681.8 | 1,687.5, range 1,667.5 to 1,716.6 |
| Reset latency in ms | 4,010.4, range 3,980.5 to 4,094.7 | 4,064.8, range 4,000.1 to 4,128.2 |

Two slots have a higher observed handoff rate in these traced flight runs. Cut and reset ranges overlap. The profile points toward host recording and submission cost, which limits the benefit available from GPU overlap. Dynamic flight poses differ and instrumentation overhead is unmeasured. The result supports the tested traced configuration and establishes no general production, physical display FPS or identical-work renderer speedup. The existing two-slot feature default remains. No different worker count was selected, so no slot sweep at another worker count was required.

Observed resource assertions pass in both configuration sweeps. Reset row ranges and half-window maxima stay within the driver's checks, and traced shutdown reaches zero rows. Native metadata allocation counters are absent at those checkpoints. These observations do not bound all heap or driver allocations and GPU bytes. Optional culling, allocation pooling and extra draw batching remain deferred. The available profile does not isolate their cost or establish a representative benefit.

## Review and delivery

The [decision trail](milestone-7.tsv) preserves failures, corrections, excluded approaches and acceptance checkpoints. The [review dispositions](m7-full-review.md) distinguish source review from runtime proof. The [principles table](m7-principles.md) names the concrete choices each principle changed.

The final trail review caught an overbroad GPU-median summary and mixed provenance in an older seven-report bundle. The workload-specific GPU values above are corrected. The [historical bundle](m7-historical-production-archive.json) is labeled mixed and cannot bind all reports to the old source run. The final passing acceptance archive is unaffected. The canonical trail retains both original mistakes and their corrections.

Fresh [trail review](m7-trail-review.md) confirms both evidence corrections and reports no flags through its documented 101-decision scope. The [delivery mapping](m7-stack.json) records four reconstructed layers and exact full-tree identity for the frame commit. Fresh [layer checks](m7-stack-checks.json) pass, including actual intermediate windows. Later metadata commits change only audit files. Ready PRs [10](https://github.com/aivv73/bend-vulkan/pull/10), [11](https://github.com/aivv73/bend-vulkan/pull/11), [12](https://github.com/aivv73/bend-vulkan/pull/12) and [13](https://github.com/aivv73/bend-vulkan/pull/13) are open and linked as one stack. The fresh [delivery audit](m7-final-delivery-review.md) reports no flags for decisions 102 through 112 and the published stack. Its verdict excludes later closure metadata, CI outcomes and merging.
