# Vulkan registry extract

`vk.xml` contains the base enum groups consumed by `tools/generate.py`.
The extract comes from the system Vulkan-Headers registry accompanying header version 363.
The original file's SHA256 is recorded in the XML comment.
The source is the [Khronos Vulkan registry](https://github.com/KhronosGroup/Vulkan-Headers/blob/main/registry/vk.xml).

The extract retains core enum values and bit positions, including core-1.0 formats, format-feature masks, memory-heap flags, and image, view, sample, layout, and attachment enums. The extract also retains selected surface, swapchain-result, presentation-layout, color-space, present-mode, transform, and alpha constants. General extension aliases are not included.
Generated output is reproducible from this checked-in extract without network access or an installed registry.

Copyright 2015-2026 The Khronos Group Inc.
SPDX-License-Identifier: Apache-2.0 OR MIT

The MIT license text is in `LICENSE-MIT`.
