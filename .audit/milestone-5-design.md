# Milestone 5 presentation design

The consumer opens a native X11 window, renders the editable 8³ cube through Vulkan, and retains movement, mouse look, carving, reset, and close controls. The existing offscreen consumer remains the headless acceptance path. Brush preview belongs to milestone 6.

## Grounding

The existing native registry uses monotonic checked keys, explicit dependencies, and one active graphics submission per device. Recorded references survive rendering completion until successful command reset or pool destruction. The new presentation state must preserve those rules.

Studied [Voltra at 8900b07e](https://github.com/amage-si/voltra/tree/8900b07e14b80d3528a3b38cb5b376774441d240). Its narrow native surface boundary, pure surface policy, delayed fence reset, and separation of frame and target resources inform this design. Its combined queue requirement and idle-based presentation retirement do not meet this checkpoint's ownership requirements.

Bend's installed `Window.frame` pumps events and draws CPU pixels with `XPutImage`. The new adapter must poll events independently. The wrapper keeps all native registry mutations on the IO loop. Balanced pure mesh preparation may run in parallel.

## Caller and data shape

`examples/voxel_interactive.bend` is the executable. A Bend presentation owner holds a world, camera, controls, mesh revision, target generation, and frame state. The world and editing policy stay outside `src/` and `Vulkan.bend`.

The checked native additions are `NativeWindow`, `Surface`, `Swapchain`, and `Semaphore`. Images have allocated or borrowed storage. A borrowed image identifies its owning swapchain and index. The swapchain key identifies its generation. Each device permits one acquisition lease across its swapchains. Every command using borrowed images must match that lease's swapchain and index. No additional public ticket handle is needed for this serial profile.

The frame uses an acquire fence, rendering fence, presentation fence, and render-finished semaphore. Its phase is explicit, such as idle, acquiring, acquired, submitted, or presenting. The next acquisition follows observed rendering and presentation completion. This trades overlap for a bounded ownership model in the first interactive checkpoint.

The target is absent or owns a complete generation. A generation contains the swapchain, interned borrowed images, views, framebuffers, one shared depth attachment, format-compatible render pass and pipeline, and extent. It does not own voxel state.

Public operations expose window poll/capture/close, surface queries, present support, device queue selection, swapchain creation/images/acquire/release/present/destruction, binary semaphores, and submission wait/signal lists. Existing device and submission constructors remain compatible and share native engines with the new operations. Generated effects come from `tools/bindings.json`.

## Ownership and completion

Windows belong to Entry. Surfaces belong to Instance and retain their window. Swapchains belong to Device and retain their surface. Borrowed image rows remain Device children and retain their swapchain. Repeated image enumeration returns the same keys. Destroying a swapchain invalidates its borrowed rows without calling `vkDestroyImage`.

Borrowed images support views, rendering, and barriers after acquisition completion. They reject explicit image destruction, memory requirements, and memory binding. Destruction checks still follow recorded references. A new acquisition rejects stale recorded references to an earlier lease.

Fence associations distinguish acquisition, rendering, and presentation. Binary semaphore states distinguish unused, pending signal, signaled, pending submit wait, pending present wait, and uncertain use. Rendering completion must not release a presentation association. Validate stage masks, duplicates, conflicting lists, ownership, and signal provenance before dispatch. Reserve fallible metadata before dispatch. Preserve the existing OOM, uncertain submission, failed reset, and sticky device-loss rules.

Presentation requires `VK_EXT_swapchain_maintenance1` and its feature. Enable its instance extension dependencies and use the extension feature query on API 1.0. Headless clients do not enable this profile or gain X11 runtime dependencies. Missing support produces an explicit startup failure.

Every present supplies a maintenance presentation fence. Observing that fence permits release of its retained resources. It does not prove visible scanout. A rendering fence or ordinary device idle cannot substitute for presentation evidence. See the [Khronos fence contract](https://docs.vulkan.org/refpages/latest/refpages/source/VkSwapchainPresentFenceInfoKHR.html) and [semaphore-reuse guidance](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).

Use bounded acquisition and fence waits, returning to event handling on timeout. Acquire uses a fence so an abandoned acquisition needs no acquire-semaphore drain. Observe acquisition, record, reset the rendering fence, submit, observe rendering, present, and observe presentation before the next acquisition. Explicit release uses maintenance1 after acquisition and rendering completion. Destruction of a drained generation may discard its acquisition even when release fails. Accepted out-of-date or surface-lost presents retain their queued waits. Present OOM preserves the prior state. Unknown present failures retain uncertain resources until actual fence evidence or known loss.

## Queue selection and recreation

Check actual surface support, formats, modes, extensions, and required usage for every candidate physical device. Prefer a common graphics/present family. Otherwise request both families, deduplicate equal entries, and use concurrent swapchain sharing across distinct families. Pools and graphics submission use the graphics queue. Presentation uses the present queue.

Recreation drains both completion domains, releases an unused acquisition, successfully resets the command, destroys the old generation, requeries capabilities, and creates with `oldSwapchain = VK_NULL_HANDLE`. This avoids retired-generation queues and the irreversible oldSwapchain replacement path. A failed build leaves an absent target and cleans its partial resources.

Preserve queried format and color-space pairs. Honor supported usage, image counts, transform, alpha, FIFO mode, fixed extents, and variable extent bounds. Handle the single undefined-format case. Rebuild format-dependent passes and pipelines and extent-dependent depth, framebuffers, viewport, scissor, and projection.

Check unmapped and zero drawable dimensions before clamping. Suspend acquisition and recreation while waiting for native events with a bounded timeout. Restore and close still work. Surface loss must report an explicit outcome and clean up safely. Full surface or device recovery may remain outside this checkpoint.

## Input and rendering

Load Xlib dynamically through the existing `-ldl` boundary. Window polling reports Base input events and drawable, focus, and capture state. It never draws CPU pixels. Release pointer capture and held controls on focus loss. Handle WM close, configure, map/unmap, keyboard, buttons, relative mouse look, and warp suppression.

Keep WASD/QE flight, RMB look, click carve, Space cut, R reset, and Escape. Derive projection and picking from one viewport definition. Scale focal pixels by height divided by 512, center at half the actual width and height, and preserve the upstream pixel-center offset. Test landscape and portrait picking against visible faces. Do not send resized coordinates to upstream fixed-512 picking.

Reuse the established packed mesh and target-independent upload, publication, and draw operations. Camera-only frames retain mesh buffers and upload counts. Replace geometry only after rendering completion and successful command reset. Keep the pinned dependencies unchanged.

## Verification and delivery

Build a repeatable native-window driver that targets only the application window. Check actual image and model changes from movement, look, click carve, demo cut, and reset. Exercise repeated nonsquare resize, capture loss, unmap/restore, continued input, and close while suspended. Check bounded resources, suspended acquisition counts, and zero final registry and metadata allocations.

Run shared and separate graphics/present families on the actual device. Check signal-to-wait submission lists with literal GPU readback because the consumer acquires with a fence. Add emitted ABI checks and controlled rollback, timeout, OOM, uncertainty, stale/foreign handle, borrowing, and lifetime probes. Keep pure selection and viewport rules in `LAWS.bend` and `PROOF.bend`.

The pre-change `python3 tools/verify.py --sanitize` run passed. Its log is `build/milestone-5-baseline.log`. The machine has a GTX 1660, X11 display, maintenance1, Khronos validation, and synchronization validation. Full headless regression and native-window validation and sanitizer runs are required after implementation.

## Throughput checkpoint

- Blocking first steps are source tracing, independent sketches, cross-judgment, and the full baseline gate.
- Independent research and design artifacts run in parallel. One implementation owner handles the coupled native API and consumer.
- Shared mutable source files have one writer. The parent owns this design note and the decision log during implementation.
- One implementation owner is the smallest safe decomposition because queue, fence, semaphore, and borrowed-image invariants share the native registry and generated API contract.

## Synthesis decision

The independent cross-judge selected candidate 2 with 24/25, compared with candidate 3 at 23/25 and candidate 1 at 20/25. The parent agrees. Use candidate 2's serial fence protocol and native lease. Graft candidate 3's destroy-then-create recreation and candidate 1's changing-count enumeration retries and undefined-format handling. Retain dynamic Xlib loading, explicit failure retention, and a shared viewport/picking owner.

Reject rolling generations, public acquisition ticket identities, per-image synchronization arrays, and commandless drains because the first checkpoint observes presentation before the next acquisition. Reject an opaque native voxel engine because world and rendering policy belong in Bend. All candidates agree that presentation completion needs separate evidence. The third runner was interrupted after its complete design artifact was available; the cross-judge evaluated that artifact.

No design blocker remains. Acceptance must prove abandoned-acquisition cleanup, present OOM retry, accepted-error presentation retention, failed reset, actual shared and separate queues, and clean teardown. Design review does not count as runtime verification.

## Implementation and verification

Bend 2.0.37 accepts one native C source per effect. The generator therefore bundles the guarded core and optional X11 adapter into `src/window.c`. Headless effects still import only `src/native.c`. Bundle freshness and headless X11/xcb linkage are executable verifier checks. This changes the planned source packaging without changing registry ownership.

The consumer initially kept stale CPU faces after edits until GPU upload. Independent parent and consumer checks reproduced two queued clicks leaving 505 occupied voxels instead of 484. CPU edits now install the body and newly prepared mesh together. Idle GPU replacement uploads that mesh after rendering completion and successful command reset. Reset followed by a queued click also restores the expected 505 voxels. The regression lives in `tests/interactive.bend`.

The final default product does not stream state diagnostics. `--trace` explicitly enables the model and allocation observations used by acceptance. Actual mouse look must change pixels relative to flight. Each landscape and portrait click must change pixels, and reset must restore the exact intact image. Pure viewport checks also assert literal off-center intersections within 0.001 cm.

`env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display` passed after the fixes. The complete log is `build/milestone-5-fix-verification-final.log`. It includes proofs, generated artifacts, previous offscreen geometry and pixel checks, semaphore GPU readback, controlled failures, validation, sanitizers, shared queues 0/0, separate queues 0/2, and the ordinary product with default quiet output. All three instrumented window runs ended with zero rows and zero tracked metadata allocations.

The parent independently passed the complete pre-fix integration gate, then reproduced its missing queued-edit regression. After the fix, the parent reran literal queued-event and viewport checks and drove an ordinary fresh product build through visible editing, exact reset, and close while unmapped. Those final logs are `build/milestone-5-parent-regression-final.log` and `build/milestone-5-parent-product-final.log`. The checked-in `docs/voxel-interactive.png` is an app-only capture after the Space demo cut.

The native correctness review passed. A focused second comment pass found no authored-comment flags after the parent rejected generated-copy and generator-refactor scope expansion. The final consumer review passed. It independently rebuilt the literal tests and rejected separate stale-cut and stale-reset mutations, then drove the ordinary product through visible editing, exact reset and suspended close. Artifacts are in `/tmp/bend-m5-followup-review-5i7ixasd`.

The independent audit-trail reviewer, gpt-6.1-sol, reported no flags. The parent also ran `bend PROOF.bend` against the final source. It exited successfully with `ALL PROOFS CHECK`. Generator freshness and `git diff --check` passed before commit.

Presentation remains Linux/X11 with required EXT maintenance1. Brush preview and full surface or device recovery remain outside milestone 5. Controlled failure probes are injected evidence and do not claim hardware-loss or real OOM testing.
