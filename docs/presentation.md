# X11 presentation

The optional Linux X11 adapter exposes explicit Vulkan surface, swapchain,
acquisition and presentation operations. Headless effects do not load X11.

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

## Consumer lifecycle

Atelier frame slots, camera controls, resize handling and live-window acceptance
belong to [bend-voxel](https://github.com/aivv73/bend-voxel/tree/main/vulkan/docs/presentation.md).
The public operations are described in the [API reference](api.md).
