# X11 presentation

The interactive consumer displays the full editable Atelier scene in a native Vulkan window. `--cube` selects the earlier basic 8³ cube regression mode.
Bend owns the world, controls, camera, picking, mesh, uploads, target generation, and frame loop.
The native wrapper owns checked handles and Vulkan dispatch. Production draws materials, sun shadows, ground and grid, exact yellow selection and three depth-aware brush rings.

## Run and verify

Use Bend 2.0.37, Linux X11, Vulkan headers, X11 headers, `libX11.so.6`, and a Vulkan driver with `VK_EXT_swapchain_maintenance1`.
The optional `src/x11.c` adapter loads Xlib through `libdl`. The generator bundles it with the guarded core in `src/window.c` for Bend's single C import.
Headless effects import only `src/native.c`.
The adapter initializes Xlib threading before opening a display and locks its pointer-warp request sequences. Vulkan may use the same display from presentation threads, as the [Xlib WSI contract](https://docs.vulkan.org/spec/latest/chapters/VK_KHR_surface/wsi.html) requires. Manual C builds still link `-ldl`, without `-lX11`.
Headless clients require no display or X11 runtime library. They retain the Vulkan 1.0 device and submission constructors.

```sh
bend examples/voxel_interactive.bend -o build/voxel-interactive
./build/voxel-interactive
```

The default uses `Camera.atelier()`. Use WASD and Q/E to move the camera. Hold RMB for relative look. Left click cuts the hovered surface with a fixed 20 cm sphere. Space cuts the current hover. R reconstructs the selected original Body while preserving the camera and controls. In `--cube` mode Space retains its fixed demo cut.
Escape and WM close exit. Capture refusal leaves the application running with look disabled.
Focus loss and unmap release capture and held movement controls. Window polling never draws CPU pixels.
Add `--trace` to print per-turn `STATE` diagnostics with camera, mesh, upload, and wrapper counters.
The window acceptance driver enables this flag, including actual graphics and presentation queue output. Normal runs are quiet.

```sh
python3 tools/verify.py --sanitize --presentation
python3 tools/verify.py --sanitize --presentation --isolated-display
```

The isolated option starts and stops a private rootful Xwayland server on the current Wayland desktop.
It avoids pointer grabs held by other X11 applications. It requires `Xwayland`, Python Pillow, and ImageMagick `import`.
The driver sends X11 key and button events to the spawned window identified by its `_NET_WM_PID`.
It uses actual pointer warps, capture, focus, configure, map, unmap, and WM close delivery.
It captures only the application window. Each run leaves its log and PNGs under `build/window-*`.

The default `tools/verify.py` suite remains headless and checks that discovery and voxel binaries have no X11 or xcb dependency. `--presentation` requires real window acceptance and never treats a skipped run as a pass.
The driver runs shared graphics/present families, distinct families, and close while suspended sequentially.
The `--split` application flag requires a distinct present family for verification.

## API profile

A presentation instance enables these extensions:

- `VK_KHR_surface`.
- `VK_KHR_xlib_surface`.
- `VK_KHR_get_physical_device_properties2`.
- `VK_KHR_get_surface_capabilities2`.
- `VK_EXT_surface_maintenance1`.

`Instance.presentation_supported` checks the swapchain extension and maintenance feature through `vkGetPhysicalDeviceFeatures2KHR`.
`Instance.create_presentation_device` enables `VK_KHR_swapchain`, `VK_EXT_swapchain_maintenance1`, and `swapchainMaintenance1`.
Missing support fails startup explicitly. The wrapper exposes no idle-based fallback for presentation retirement.

| Operation | Result or contract |
| --- | --- |
| `Entry.open_window` | Checked `NativeWindow` owned by the Entry. |
| `NativeWindow.poll` | Dimensions, mapped/focus/capture state, and Base events. A wait is bounded to at most 1,000 ms. |
| `NativeWindow.capture` | The resulting capture state. Refused capture returns `False`. |
| `Instance.create_surface` | Surface owned by the Instance, retaining a window from the same Entry. |
| `Instance.surface_capabilities`, `surface_formats`, `present_modes`, `present_support` | Queries on a physical device and surface from the same Instance. |
| `Instance.create_presentation_device` | Graphics and present families, deduplicated when equal. |
| `Device.create_swapchain` | Validated format/color-space pair, count, extent, usage, transform, alpha, and present mode. |
| `Device.swapchain_images` | Interned borrowed `ImageHandle` keys. |
| `Device.acquire` | Explicit acquisition outcome, using a caller fence and U64 timeout. |
| `Device.release_acquired` | Maintenance release after acquisition and any rendering complete. |
| `Device.submit_synced` | One command and fence with binary wait/stage and signal lists. |
| `Device.present` | Matching rendered lease, render-finished semaphore, and maintenance presentation fence. |

Separate queue families use concurrent swapchain sharing. Command pools and submission use the graphics queue.
Presentation uses the present queue. Surface policy prefers a common family and otherwise chooses distinct supported families.
The selection checks supported surface formats and FIFO mode before creating a device.
UNORM formats are preferred for the existing packed palette. A single undefined surface format permits BGRA8 UNORM with the reported color space.

Borrowed images support views before acquisition and barriers/rendering after acquisition completion.
They reject direct destruction, memory requirements, and binding. Stale keys and wrong-owner handles reject before Vulkan dispatch.
Destroy views and reset recorded references before destroying a swapchain. Destroy the surface before its window.
`Entry.with` closes the complete dependency tree after either a successful callback or a callback failure.

## Frame and failure states

The frame has separate acquisition, rendering, and presentation fences, plus one binary render-finished semaphore.
The phases are idle, acquiring, submitted, and presenting. Each phase returns to native event processing on timeout.
The rendering fence resets after recording succeeds and immediately before submission. Acquisition paths that skip submission never reset it.

Acquisition returns `Acquired{index, suboptimal}`, `AcquireOutOfDate`, `AcquireNotReady`, `AcquireTimeout`, or `AcquireSurfaceLost`.
Suboptimal and out-of-date request recreation. Timeout and not-ready preserve the generation.
Surface loss ends this checkpoint with an explicit error and cleanup. Full surface and device recovery remain outside its scope.
An acquired frame may be released after its acquire fence completes, without draining an acquire semaphore.

Presentation returns `Presented`, `PresentSuboptimal`, `PresentOutOfDate`, or `PresentSurfaceLost`.
Accepted out-of-date and surface-lost results retain their queued semaphore waits until presentation-fence evidence.
Present OOM leaves the rendered lease and semaphore unchanged for retry.
Semaphore signal provenance includes the acquisition sequence, so a signal from an earlier lease cannot present a later image.
Unknown acquire, submit, and present failures retain uncertain ownership. Fallible metadata reservation precedes irreversible dispatch.
A failed reset preserves recorded references. Known device loss permits scoped teardown.

A render fence proves graphics completion. It does not retire a present wait.
`Device.wait_idle` completes graphics state while preserving presentation associations.
Every present supplies `VkSwapchainPresentFenceInfoEXT`. Its fence proves that the associated resources can be released.
That fence does not prove visible scanout. The consumer observes it before acquiring another image.
The [Khronos fence contract](https://docs.vulkan.org/refpages/latest/refpages/source/VkSwapchainPresentFenceInfoKHR.html) defines this distinction.
If cleanup cannot establish completion, it reports a failure and keeps the resource tree live.

Recreation observes both completion domains, resets the command, destroys the old target, and requeries the surface.
It creates with `oldSwapchain = NULL`. A failed target build destroys its partial resources and produces no target.
Each generation rebuilds format-compatible passes/pipelines and extent-dependent depth, views, and framebuffers.
Unmapped and zero-sized windows suspend acquisition before extent clamping and poll with a 50 ms timeout.

## Projection and editing

The viewport centers rays at half the actual width and height and keeps the upstream half-pixel offset.
Focal pixels scale by height divided by 512. The camera matrix uses the same scale with the actual aspect ratio. Pointer coordinates map to the current target extent during recreation.
Picking scans front-facing intersections without the upstream renderer's fixed-512 tile or projection cull. It follows the renderer's back-face culling when the camera enters solid geometry.
Landscape and portrait resize therefore preserve agreement between displayed faces and edits.

The consumer reuses the packed mesh, upload, publication, and indexed draw helpers used by the offscreen renderer.
Each cut and reset prepares the CPU body and picking mesh together, so queued clicks use the current surface before upload.
World owns CPU Body and Mesh, original scene choice, camera, controls, uncaptured pointer, dirty state and CPU geometry revision. Session owns the single GPU geometry group, installed revision and upload count beside the existing frame phase and target state. Camera changes retain mesh buffers and uploads.
After acquisition-fence SUCCESS, the loop installs the latest prepared CPU mesh, computes hover, exact selected cells, camera, viewport and the 2,336-byte frame from that revision, then uploads and records before processing another event batch. Events received while Submitted or Presenting remain dirty for the next frame. Host writes occur only after previous completion and command reset.

Move and button events refresh the uncaptured pointer. Captured look and edits deliberately use the current viewport center. Ground is not pickable and does not write the voxel depth that hides rings.

The stable scene group retains descriptors, uniform, sampler, fixed 512-square shadow resources, layouts and ring indices during resize. The target rebuilds world, background and ring pipelines against its actual format and render pass. Partial construction unwinds in dependency order. Both native presentation and offscreen readback call `Scene.record`; their output ownership remains separate.

## Evidence boundaries

`tests/semaphores.bend` verifies binary signal-to-wait submission with literal GPU readback.
`tests/interactive.bend` checks literal occupied-voxel counts after queued cuts and reset before upload, plus a cavity hit within 0.001 cm.
`tests/viewport.bend` checks off-center landscape and portrait hits against literal intersections with the cube's y=0 plane within 0.001 cm.
`tests/presentation_abi.bend` checks emitted records, Boolean fields, events, outcomes, wait descriptions, and U64 limbs.
`tools/check_native.py` controls semaphore allocation failure, OOM, uncertainty, and signal retention beside actual GPU tests.
`tools/check_presentation.py` controls changing image counts, interning, allocation rollback, uncertain acquisition, present OOM retry, accepted errors, and independent presentation retention.
It also injects a pipeline failure into the Bend target builder and checks that every partial resource is released.
These injected outcomes do not claim driver or hardware failure coverage.

`tools/check_window.py` requires visible image changes and model changes for camera and edits.
Each resized edit must change pixels, and reset must restore the intact image at the same camera and extent.
Its `--product` check builds the ordinary executable, verifies default quiet output, compares actual cut and reset pixels, and closes the unmapped window.
It checks capture loss, repeated non-square recreation, suspension, restore, continued input, Escape, and WM close.
A native dispatch counter verifies that acquisition stops while the window is unmapped.
The emitted test allocator bounds wrapper metadata and requires zero allocations and zero registry rows after shutdown.
ASan driver-global leak detection is disabled. Wrapper counters remain explicit.
Pure laws cover queue selection, formats, image counts, suspension, extent selection, and pixel-center units.
They do not prove floating-point calculations, native effects, Vulkan drivers, or shaders.

`tools/check_atelier_window.py` drives actual default Atelier runs with graphics and presentation queue families 0/0 and 0/2. It checks images after settled-hover clicks, Space and reset, revisions and upload counts, flight and relative look, resize, suspension and remapping and zero-row shutdown. `tools/check_window.py` retains explicit `--cube` regression invocations; its quiet-product check uses default Atelier and settles hover before capturing the intact image. A pointer-only image change cannot count as carving.

`tests/appearance_acquisition.bend` acquires a real native image, queues edits and changes to the camera and hover during Acquiring, then checks actual device geometry and all 2,336 frame bytes against that recorded revision. It also queues pointer input during Submitted and flight during Presenting and requires dirty state to survive completion and command reset. `tests/interactive.bend` covers button coordinates without a prior Move and capture-release pointer state.

The complete milestone 6 gate passed with `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display`. Actual Atelier app-only captures and traces remain under `build/milestone-6-atelier-window-*`; quiet product captures remain under `build/window-product-*`. The [appearance contract](voxel.md#production-appearance-and-evidence) states exact identity, lighting and shadow comparison limits.
