# Vulkan / examples / voxel split

The in-tree consumer described in the initial evidence below was subsequently
moved to `/home/aivv/Документы/projects/bend-voxel/vulkan`. The reverse voxel
submodule was removed. bend-voxel now owns the renderer and pins bend-vulkan.
The initial results below describe the first, in-tree separation; cross-repository
validation is recorded in bend-voxel’s `vulkan/docs/migration.md`.

Baseline: `65c79f6a70f8b6c9069bbee108d97540d464bba5`.

Environment: Linux `7.3.0-4-cachyos`, x86-64; Bend `2.0.39`; Clang
`23.1.4`; Python `3.14.8`; NVIDIA GeForce GTX 1660. Khronos and
synchronization validation are available.

Pinned dependencies are unchanged:

- bend-collections: `bc78c4f4cabb536a2a1dd6e308b6a8f0afafda7c`
- optional bend-voxel: `cdfd92d356229c5de5f4aaddd358f15ec3686dd4`

The original verifier passed measurement checks, timing-reset injection, shader
freshness and `bend PROOF.bend`. It was stopped during geometry acceptance to
perform the split; this is not a claim that the complete original gate was rerun.
The original source remains available at the baseline commit.

## Ownership

- `Vulkan.bend`, `src/`, `tests/` and the root proofs describe the general API.
- `examples/` contains general examples and their runnable acceptance entry point;
  `shaders/` contains only general indexed/descriptor fixtures.
- `consumers/voxel/` owns all voxel renderer modules, entry points, shaders,
  consumer-coupled tests, oracles, measurement tools, laws and proofs.
- Shared example and API test helpers remain reusable by the consumer. There is
  no import in the opposite direction. `tools/check_layers.py` checks this.
- The optional voxel gitlink remains at its existing path. Library setup and
  verification require only bend-collections.

All 111 root law statements were preserved: 64 API laws and 47 consumer laws.
Relocated Bend, C and GLSL bodies were compared with the baseline after removing
import lines and are unchanged. Native library code is unchanged. Parallel
geometry and chunk construction are retained. Generated SPIR-V is partitioned
between the two shader generators; both freshness checks pass.

## Acceptance

- `python3 tools/verify.py --sanitize`: passed, including general examples,
  native failure probes, ASan/UBSan and Khronos/synchronization validation.
- The same command passed in a fresh temporary source tree containing only
  `Vulkan.bend`, root laws/proofs, `src`, `examples`, `shaders`, `tests`, `tools`,
  `registry` and bend-collections. Neither `consumers/voxel` nor bend-voxel was
  present. No pre-existing build artifacts were copied.
- Atelier quiet-product window acceptance passed (edit pixels, exact reset,
  suspended close) on a private Xwayland display. The first run timed out at
  exact reset; the unchanged baseline and a rerun of the same relocated binary
  passed. No screenshot tolerance or application logic was changed.
- Consumer measurement, geometry/chunk determinism, generation/retirement,
  installation/upload rollback, appearance math, reference lighting and shader
  GPU acceptance passed. Shader GPU checks included sanitizers; production
  image comparisons passed normally and with Vulkan validation.
- Both `bend PROOF.bend` and `bend consumers/voxel/PROOF.bend` passed.

The full consumer `--sanitize` run was stopped during the production renderer’s
Clang sanitizer compilation after more than 13 minutes in that compile step.
This is an incomplete optional sanitizer gate, not a passing full consumer
`--sanitize` run. No test, timeout, compiler flag or tolerance was weakened.
The remaining checks passed separately: actual-GPU-depth reference comparison,
shadow causality with five negative controls, geometry-device and voxel-offscreen
acceptance (also with Vulkan validation), viewport and queued input checks,
headless linkage, and preprocessed CPU builds without CUDA dispatch.
The broad instrumented `--presentation` suite was preserved but not rerun; the
quiet-product Atelier window check was run as described above.

This split does not implement the roadmap's new interactive non-voxel camera
example, ECS integration, or other later engine milestones.
