# API reference

The public module is `Vulkan.bend`. Vulkan constants are zero-argument definitions in `src/constants.bend`, with their original `VK_` names.
`src/core.bend` provides API-version encoding, flag predicates, queue-family selection, memory-type selection, and U64 limb conversion.

Operations return `IO(VkResult(A))`, except `write_memory_words`, which returns its array beside the result. `VkResult(A)` is `Result<&1, &1, (U32 & String), A>`.
The `U32` in an error is the exact two's-complement bit pattern of a Vulkan `VkResult`, or a wrapper error from the table below.
The string names the failed operation or invalid input.

| Wrapper code | Meaning |
| --- | --- |
| `0x60000001` | Loader unavailable or JavaScript backend unsupported |
| `0x60000002` | Unknown, stale, wrong-kind, or wrong-owner handle |
| `0x60000003` | Invalid argument or unsupported memory access range |
| `0x60000004` | Resource still referenced or invalid command state |
| `0x60000005` | Registry, allocation, enumeration, or copy limit |

`Entry.with` preserves the callback's failure code. If cleanup also fails, its diagnostic is appended to the message.
If cleanup alone fails, the scope returns that failure.

## Entry and instance operations

| Operation | Result |
| --- | --- |
| `Entry.load()` | A loader entry |
| `Entry.enumerate_instance_version(entry)` | Loader API version, with a Vulkan 1.0 fallback |
| `Entry.enumerate_instance_layers(entry)` | Layer names, specification/implementation versions, and descriptions |
| `Entry.enumerate_instance_extensions(entry, layer)` | Extension names and specification versions |
| `Entry.create_instance(entry, info)` | An instance |
| `Entry.close(entry)` | Cascading resource teardown and library unload |
| `Instance.enumerate_physical_devices(instance)` | A list of physical devices |
| `Instance.get_physical_device_properties(instance, physical)` | Name, API version, driver version, vendor ID, device ID, and type |
| `Instance.get_physical_device_queue_family_properties(instance, physical)` | A list of `(flags, queue_count)` pairs indexed by family |
| `Instance.get_physical_device_memory_properties(instance, physical)` | A list of `Core.MemoryType{property_flags, heap_index}` indexed by memory type |
| `Instance.enumerate_device_extensions(instance, physical, layer)` | Device extension names and specification versions |
| `Instance.get_physical_device_memory_heaps(instance, physical)` | `MemoryHeap{size, flags}` values |
| `Instance.get_physical_device_format_properties(instance, physical, format)` | Linear/optimal tiling and buffer feature masks |
| `Instance.get_physical_device_image_format_properties(instance, physical, info)` | Exact image configuration limits as `ImageFormatProperties` |
| `Instance.get_physical_device_limits(instance, physical)` | The selected `PhysicalDeviceLimits` fields |
| `Instance.create_device(instance, physical, info)` | A device with one queue at priority 1.0 |
| `Instance.destroy(instance)` | Instance teardown, rejecting live devices or surfaces |

`InstanceCreateInfo{application_name, api_version, layers, extensions}` accepts explicit layer and extension names.
`InstanceCreateInfo.default()` requests Vulkan 1.0, with no layers or extensions.
`DeviceCreateInfo{queue_family_index, extensions}` selects one queue and enables no optional device features.
Strings containing NUL are rejected. Allocation callbacks are null.
Physical devices are interned within an instance and invalidated when the instance is destroyed.
Layer arguments are `Maybe<String>`. `None` queries global extensions. `Some{name}` forwards that explicit layer name.
Names containing NUL reject. Empty enumerations are valid. Counts are bounded to 4096 and VK_INCOMPLETE retries to eight attempts.
A final Vulkan error, including VK_INCOMPLETE, retains its exact bits. Extension queries preserve the loader's result for the requested layer.
Format queries accept core Vulkan 1.0 enum values 0 through 184 and return raw feature masks.
Discovery does not enable extensions, features, or layers.

`PhysicalDeviceLimits` has these ten U32 fields in order:

- `max_image_dimension_2d`, `max_framebuffer_width`, and `max_framebuffer_height`.
- `max_color_attachments` and `max_push_constants_size`.
- `max_vertex_input_attributes`, `max_vertex_input_bindings`, `max_vertex_input_attribute_offset`, and `max_vertex_input_binding_stride`.
- `max_memory_allocation_count`.

Its final four fields are upstream W.U64 values, `non_coherent_atom_size`, `optimal_buffer_copy_offset_alignment`, `optimal_buffer_copy_row_pitch_alignment`, and `buffer_image_granularity`.
Copy-alignment limits do not impose an alignment restriction on buffer-to-buffer byte copies.

## Buffers and memory

| Operation | Result |
| --- | --- |
| `Device.create_buffer(device, BufferCreateInfo{size, usage})` | An exclusive, non-sparse buffer |
| `Device.get_buffer_memory_requirements(device, buffer)` | `MemoryRequirements{size, alignment, memory_type_bits}` |
| `Device.allocate_memory(device, size, memory_type_index)` | An allocation |
| `Device.bind_buffer_memory(device, buffer, memory, offset)` | A binding after size, alignment, type, and owner checks |
| `Device.write_memory(device, memory, offset, bytes)` | Checked host write, including flush for noncoherent memory |
| `Device.write_memory_words(device, memory, offset, byte_length, words)` | Original `Array<U32>` beside `VkResult(Unit)` |
| `Device.read_memory(device, memory, offset, count)` | Byte list, including invalidation for noncoherent memory |
| `Device.destroy_buffer(device, buffer)` | Buffer teardown |
| `Device.free_memory(device, memory)` | Allocation teardown, rejecting bound buffers and images |
| `Device.wait_idle(device)` | Device completion |
| `Device.destroy(device)` | Device teardown, rejecting live resources |

Sizes, offsets, and alignments are `bend-collections` `W.U64` values.
`Core.whole_size()` returns Vulkan's all-ones `VK_WHOLE_SIZE` value.
`Core.find_memory_type(types, memory_type_bits, required_flags)` returns the first eligible index or `None`.
`Core.find_queue_family(families, required_flags)` skips empty queues and returns the first matching family.

A byte list contains U32 values from 0 through 255. Host reads and writes require host-visible memory.
Each host operation maps the whole allocation temporarily and copies a checked subrange.
`read_memory` takes a U32 byte count. Host reads and both upload paths are limited to 16 MiB per call.
Memory allocation sizes and copy offsets retain all 64 bits.
Packed uploads emit each word's low-order byte first and truncate the final partial word.
The explicit U64 byte length must fit the array capacity, allocation range, and 16 MiB chunk limit.
Zero bytes at an in-bounds offset is valid. Every outcome returns the unchanged array, including the interpreted backend's native-only error.
A flush failure can leave mapped destination bytes changed.
No Bend heap pointer survives the operation.

The wrapper checks common lifetime and memory-access errors. Callers remain responsible for Vulkan validity requirements for chosen flags, extensions, and resource use.
Handle keys are checked process-local identifiers. They provide no raw Vulkan handle interoperation or access-control guarantee.

## Images and views

| Operation | Result |
| --- | --- |
| `Device.create_image(device, info)` | An unbound `ImageHandle` |
| `Device.get_image_memory_requirements(device, image)` | `MemoryRequirements{size, alignment, memory_type_bits}` |
| `Device.bind_image_memory(device, image, memory, offset)` | An explicit requirements-checked binding |
| `Device.create_image_view(device, info)` | An `ImageView` retaining its image |
| `Device.destroy_image_view(device, view)` | View teardown, rejecting framebuffer dependents |
| `Device.destroy_image(device, image)` | Image teardown, rejecting views and recorded references |

`ImageHandle` avoids a name collision with Bend Base's `Image` type.
`ImageCreateInfo{format, extent, mip_levels, array_layers, usage}` creates an exclusive 2D optimal-tiled image.
Depth is one, samples are one, flags are zero, and initial layout is UNDEFINED.
Extent and mip/layer counts must be positive and fit the exact configuration limits and full mip chain.
Creation checks configuration support and required format features before native creation.
The returned memory requirements determine allocation size. Logical texel bytes do not describe an optimal image's footprint or memory layout.

The creation profile accepts these formats when the driver supports the requested configuration:

| Format | Value | Aspect | Raw texel bytes |
| --- | --- | --- | --- |
| `VK_FORMAT_R8G8B8A8_UNORM` | 37 | COLOR | R, G, B, A |
| `VK_FORMAT_R8G8B8A8_SRGB` | 43 | COLOR | Encoded R, G, B, linear A |
| `VK_FORMAT_B8G8R8A8_UNORM` | 44 | COLOR | B, G, R, A |
| `VK_FORMAT_B8G8R8A8_SRGB` | 50 | COLOR | Encoded B, G, R, linear A |
| `VK_FORMAT_D16_UNORM` | 124 | DEPTH | Two little-endian UNORM bytes |
| `VK_FORMAT_D32_SFLOAT` | 126 | DEPTH | Four little-endian IEEE binary32 bytes |

Usages are a nonempty subset of TRANSFER_SRC, TRANSFER_DST, SAMPLED, COLOR_ATTACHMENT, and DEPTH_STENCIL_ATTACHMENT.
Color and depth attachment usages must match the format's role. Stencil, linear tiling, MSAA, compressed formats, sparse images, and format reinterpretation are absent.
SAMPLED usage permits resource preparation. Descriptors, samplers, and shader sampling commands are absent.

`ImageFormatInfo{format, image_type, tiling, usage, flags}` queries recognized core-1.0 configurations beyond the creation profile.
Invalid enum values return the wrapper argument error. A driver rejection preserves exact `VK_ERROR_FORMAT_NOT_SUPPORTED` bits, `4294967285`.
Failed query outputs are never decoded.
`ImageFormatProperties` contains `max_width`, `max_height`, `max_depth`, `max_mip_levels`, `max_array_layers`, `sample_counts`, and `max_resource_size: W.U64`.
Generic format masks alone do not establish support for a configuration.

`ImageSubresourceRange{aspect_mask, base_mip_level, level_count, base_array_layer, layer_count}` requires explicit positive counts and the format's exact aspect.
`ImageViewCreateInfo{image, view_type, range}` requires binding and at least one view-eligible usage, SAMPLED or an attachment usage.
Views use the image's format and identity component mapping. A 2D view selects one layer. A 2D_ARRAY view may select multiple layers.

Buffer and image bindings share requirements-sized bounds, alignment, type, and owner checks.
Buffer-buffer aliasing remains available. Binding intervals must not overlap when either resource is an image.
Mixed buffer/optimal-image intervals must also occupy disjoint `buffer_image_granularity` pages, in either bind order.
Distinct images may share an allocation at disjoint requirements intervals. Allocation-wide host exclusion still applies.

## Image commands and readback

| Operation | Result |
| --- | --- |
| `CommandBuffer.clear_color_image(command, image, layout, value, ranges)` | Float color clear over explicit ranges |
| `CommandBuffer.clear_depth_image(command, image, layout, depth, ranges)` | Depth clear over explicit ranges |
| `CommandBuffer.copy_buffer_to_image(command, src, dst, layout, regions)` | Raw buffer upload |
| `CommandBuffer.copy_image_to_buffer(command, src, layout, dst, regions)` | Raw staging readback |

Image commands require bound, same-device resources and Recording Outside scope.
Clears and uploads require TRANSFER_DST usage and TRANSFER_DST_OPTIMAL or GENERAL layout.
Readback requires TRANSFER_SRC usage and TRANSFER_SRC_OPTIMAL or GENERAL layout.
Color clear requires a graphics or compute queue. Depth clears and depth copies require graphics.
Color copies accept graphics, compute, or transfer queues and enforce the selected family's actual `minImageTransferGranularity`.
Zero granularity requires a whole mip. Nonzero granularity permits the Vulkan edge exception.
Range and copy lists are nonempty and bounded to 4096. Overlapping clear ranges are rejected.

`ClearColor{r, g, b, a}` takes finite F32 values. Vulkan converts them to the destination format, including sRGB encoding of RGB.
Copies preserve stored bytes and perform no color conversion, swizzle, vertical flip, or alpha transformation.
Depth clears require finite values in `[0,1]`. Uploaded depth values must also be in `[0,1]`, as a caller obligation.
The wrapper does not inspect GPU buffer contents to validate uploaded depth values.

`BufferImageCopy{buffer_offset, buffer_row_length, buffer_image_height, image_subresource, image_offset, image_extent}` uses a W.U64 byte offset into the buffer.
The offset is relative to the buffer, independently of its memory binding offset.
`buffer_row_length` and `buffer_image_height` are texel counts. Zero means the copied width or height.
Positive values must cover those dimensions. `ImageSubresourceLayers{aspect_mask, mip_level, base_array_layer, layer_count}` selects one mip and positive layer count.
Offsets are nonnegative and signed-representable. Extents must be positive, signed-representable, and fit the selected mip.
Buffer offsets are four-byte aligned, including D16. Row byte lengths cannot exceed `INT32_MAX`.

For normalized row length R, image height H, bytes per texel B, width w, height h, layers L, and buffer offset O:

```text
row_stride   = R * B
layer_stride = H * row_stride
end          = O + (L - 1) * layer_stride + (h - 1) * row_stride + w * B
```

All arithmetic is checked U64. The final row has no required trailing padding.
The interval must fit the buffer's logical size and its bound allocation.
Uploads reject overlapping destination image boxes. Downloads reject overlapping destination buffer envelopes, including their internal padding.
Repeated source reads are allowed. Logical dimensions and strides determine the result, independently of Bend array capacity.
Texels increase in x, then y, then layer order. The example defines the first row, `y=0`, as the top.
Positive-height viewport coordinates map NDC negative Y toward the first row, as described in the indexed graphics contract.

Layouts and initialized contents are caller assertions at execution time.
The wrapper stores no layout cache and inserts no implicit image or host barriers.
Use `ImageMemoryBarrier{image, range, old_layout, new_layout, src_access, dst_access}` in the sole `pipeline_barrier` operation.
The wrapper checks usage, aspect, range, layout enum, and queue stage/access compatibility.
Both queue-family indices are IGNORED. Overlapping image ranges within one barrier call are rejected.
UNDEFINED is an old discard layout only and requires zero source access by wrapper policy.
After unexpected submission errors, observe idle recovery and deliberately overwrite, discard, or recreate before relying on contents.

## Render passes and framebuffers

| Operation | Result |
| --- | --- |
| `Device.create_render_pass(device, info)` | A Vulkan 1.0 single-subpass `RenderPass` |
| `Device.create_framebuffer(device, info)` | A one-layer `Framebuffer` retaining its pass and ordered views |
| `Device.destroy_framebuffer(device, framebuffer)` | Teardown, rejecting recorded command references |
| `Device.destroy_render_pass(device, pass)` | Teardown, rejecting framebuffers and graphics pipelines |
| `CommandBuffer.begin_render_pass(command, framebuffer, area, clears)` | Enter Recording Inside scope |
| `CommandBuffer.end_render_pass(command)` | Return to Recording Outside scope |

`RenderPassCreateInfo{colors, depth}` contains ordered `AttachmentInfo{format, load_op, store_op}` values and an optional depth attachment.
At least one attachment is required. Color count is limited by `max_color_attachments` and the wrapper's 4095-color cap.
LOAD, CLEAR, DONT_CARE and STORE, DONT_CARE operations are supported.
Attachments are single-sample. Stencil operations are DONT_CARE. The queue must support graphics.
Initial, subpass, and final layouts are all COLOR_ATTACHMENT_OPTIMAL or DEPTH_STENCIL_ATTACHMENT_OPTIMAL for the corresponding role.
There are no explicit subpass dependencies. Supply outside barriers for transfers and attachment reads/writes, including LOAD of a prior pass's output.

`FramebufferCreateInfo{render_pass, attachments, extent}` requires same-device, ordered, format-matching 2D views.
Each view selects exactly one mip and one layer, has the required attachment usage, and covers the framebuffer extent.
Attachment subresources cannot overlap. Begin derives the exact pass identity from the framebuffer.
`RenderArea{offset, extent}` has nonnegative offsets and positive extents, all signed-representable and within the framebuffer.

The clear list has one entry per attachment, including placeholders.
CLEAR slots require `ColorClear{ClearColor{...}}` or `DepthClear{depth}` according to role.
Other slots require `UnusedClear{}`. Float constraints match image clears.
Clears cover the render area. Preserved pixels outside that area require prior initialization and correct synchronization.
Nested begin, unmatched end, and command end Inside reject before dispatch.
All fills, copies, image clears, and barriers reject Inside. Successful reset may discard an open recording.
Indexed graphics commands use this same Vulkan 1.0 pass scope.

## Shaders, layouts, and graphics pipelines

| Operation | Result |
| --- | --- |
| `Device.create_shader_module(device, words)` | A checked `ShaderModule` from `List<U32>` |
| `Device.create_pipeline_layout(device, info)` | A checked `PipelineLayout` |
| `Device.create_graphics_pipeline(device, info)` | A checked `GraphicsPipeline` |
| `Device.destroy_shader_module(device, shader)` | Shader teardown |
| `Device.destroy_pipeline_layout(device, layout)` | Teardown, rejecting pipeline dependents |
| `Device.destroy_graphics_pipeline(device, pipeline)` | Teardown, rejecting recorded references |

Shader words contain SPIR-V 1.0, at least five words and at most 16 MiB.
The boundary checks magic `0x07230203`, version `0x00010000`, a nonzero ID bound, and a zero schema word.
These header checks do not validate shader instructions, capabilities, interfaces, or memory accesses.
The library consumes the list and copies native aligned words. No Bend pointer survives the effect.
Shader modules are creation inputs. They can be destroyed after pipeline creation.

`PipelineLayoutCreateInfo{push}` has `None{}` or `Some{PushConstantRange{stages, bytes}}`.
The sole optional range starts at byte zero. Its nonzero stage mask is a subset of VERTEX and FRAGMENT.
Its size is a multiple of four, between 4 and 128 bytes, and within the device limit.
There are no descriptor set layouts.

`GraphicsPipelineCreateInfo` has these fields in order:

- `layout`, `render_pass`, `vertex`, and `fragment` are checked same-device handles.
- `bindings` contains `VertexInputBinding{binding, stride, input_rate}`. Strides are bytes. Rates are VERTEX or INSTANCE.
- `attributes` contains `VertexInputAttribute{location, binding, format, offset}`. Offsets are bytes within a record.
- `topology` is TRIANGLE_LIST or TRIANGLE_STRIP.
- `raster` is `RasterState{cull_mode, front_face}`. Cull flags permit NONE, FRONT, BACK, or both. Front face is CLOCKWISE or COUNTER_CLOCKWISE.
- `depth` is `None{}` or `Some{DepthState{test, write, compare}}`. Compare accepts the eight core comparison operations.
- `color_write_mask` contains R, G, B, and A component bits. One mask applies to every color attachment.

The profile fixes vertex and fragment entrypoints to `main`, fill rasterization, line width one, one sample, subpass zero, and dynamic viewport/scissor.
Primitive restart, depth clamp/bias, stencil, blending, logic operations, and optional device features are disabled.
Depth testing or writing requires a depth attachment. An absent depth state disables both.
Pipelines retain their layout and exact render pass through the dependency graph.

Binding numbers and attribute locations are unique and within device limits. Attributes reference declared bindings.
The wrapper caps binding descriptions at 64 and attribute descriptions at 256, in addition to device limits.
Supported vertex formats are R32_SFLOAT, R32G32_SFLOAT, R32G32B32_SFLOAT, R32G32B32A32_SFLOAT, and R8G8B8A8_UNORM.
Creation also checks the driver's VERTEX_BUFFER format feature.
Float components require four-byte attribute offsets and strides. RGBA8 components have one-byte alignment.
Each immutable binding requirement records its alignment and maximum attribute end, so vertex binding checks first-record coverage independently of stride.

## Indexed graphics recording

| Operation | Result |
| --- | --- |
| `CommandBuffer.bind_graphics_pipeline(command, pipeline)` | Bind a pipeline and clear vertex/push readiness |
| `CommandBuffer.set_viewport(command, viewport)` | Set the sole dynamic `Viewport{x,y,width,height,min_depth,max_depth}` |
| `CommandBuffer.set_scissor(command, area)` | Set the sole dynamic scissor from `RenderArea` |
| `CommandBuffer.bind_vertex_buffer(command, binding, buffer, offset)` | Bind one declared vertex binding at a W.U64 byte offset |
| `CommandBuffer.bind_index_buffer(command, buffer, offset, index_type)` | Bind UINT16 or UINT32 indices at a W.U64 byte offset |
| `CommandBuffer.push_constants(command, words)` | Initialize the bound layout's entire push block from `List<U32>` |
| `CommandBuffer.draw_indexed(command, draw)` | Record an indexed draw after readiness and range checks |

These commands require Recording and a graphics queue. Bindings and dynamic state may be set Outside or Inside a pass.
A pipeline must precede vertex bindings and pushes. Every pipeline bind, including a repeated bind, clears all vertex readiness and push readiness.
A layout without a push range is immediately push-ready. A push command requires a nonempty declared block and exactly its word count.
The wrapper uses the bound pipeline's layout, declared stages, and offset zero. Partial updates are absent.
Index, viewport, and scissor readiness persist across pipeline binds.
All graphics readiness persists across begin/end-pass within a recording. Draw still requires the active framebuffer's exact pass identity.
Successful begin starts with zero readiness. End, completion, invalidation, and either reset result clear the expanded command payload.
Failed commands leave readiness and recorded references unchanged.

Vertex and index buffers require bound memory and the corresponding usage bits.
Alignment includes both the buffer's memory binding offset and the command's relative offset.
Index alignment is two bytes for UINT16 and four bytes for UINT32.
Vertex alignment follows the pipeline's component requirements. The first attribute record must fit after the relative offset.
Offsets retain all U64 bits. Draw checks the index byte span with widened arithmetic and division before dispatch.

`IndexedDraw{index_count, instance_count, first_index, base_vertex, first_instance}` uses `BaseVertex{bits}` for an int32 value's two's-complement U32 bits.
For example, `4294967293` means -3 and `2147483648` means INT32_MIN. All U32 bit patterns decode to an int32.
The wrapper never reads index contents and does not validate effective index-plus-base values or subsequent vertex/instance fetch bounds.

Viewport floats must be finite. Width and height are positive and within `maxViewportDimensions`.
Coordinates and their far edges fit `viewportBoundsRange`. Both depth endpoints are in `[0,1]`.
Negative viewport height is outside this Vulkan 1.0 profile. Scissor offsets are nonnegative and offset-plus-extent fits INT32_MAX.
A zero scissor extent is allowed. Draw requires every declared vertex binding, an index buffer, both dynamic values, and a complete push block.

Every mentioned pipeline and vertex/index buffer remains referenced, including overwritten bindings.
Observed completion permits host access but keeps those roots. Successful reset or pool destruction releases them.
Pending and Uncertain commands exclude host access to reached allocations, including overwritten vertex/index resources.
Shader semantics, capabilities, stage interfaces, valid index contents, vertex/instance fetch bounds, image layouts, and synchronization remain caller obligations.
Shaders must match the descriptor-free layout and the declared vertex inputs, push block, and attachment outputs.

## Example mesh and camera contract

`examples/indexed_offscreen.bend` owns its mesh packing and camera policy.
Each vertex is 24 bytes, with a vec3 position at byte zero and a vec3 flat RGB color at byte 12.
Both attributes use R32G32B32_SFLOAT. Mesh bytes start at vertex-buffer offset 16.
Index data starts at offset 8, includes an unused first index, and uses `first_index` values 1 and 7 with base vertex -3.
The example exercises both little-endian UINT16 and UINT32 payloads.

The generic 64-byte push block contains a GLSL column-major `mat4` multiplying a column vector.
Its columns are `(0.5,0,0,0)`, `(0.25,0.5,0,0)`, `(0,0,1,0)`, and `(0.25,-0.25,0,1)`.
The nonsymmetric matrix exposes transposition and word-order errors. Changing its final column moves the camera without rebuilding the mesh.
The GLSL block starts at byte zero and each column occupies 16 bytes.
Clip depth is `0 <= Z <= W`. The positive-height viewport maps negative NDC Y toward row zero, which the example calls the top.
Readback is row-major RGBA8 and little-endian D32, without a vertical flip.

`tools/build_shaders.py` compiles GLSL with `glslc --target-env=vulkan1.0`, validates with `spirv-val`, and embeds words through explicit little-endian decoding.
The library invokes no GLSL compiler. Rebuild with `python3 tools/build_shaders.py`; check freshness with `--check`.
The indexed acceptance compares every color and depth pixel against literal values.
Its external rectangle and clip boundaries lie between pixel centers. Shared triangle diagonals have identical color/depth on both sides.
The test compares the union of those triangles, so diagonal edge ownership cannot change the expected result.
Near/far plane crossings have literal D32 expectations at the surviving pixel centers.

## Command submission

| Operation | Result |
| --- | --- |
| `Device.create_command_pool(device)` | A pool for the device's selected queue family |
| `Device.allocate_command_buffer(device, pool)` | One primary command buffer |
| `CommandBuffer.begin(command)` | Begin one-time recording |
| `CommandBuffer.fill_buffer(command, buffer, offset, size, data)` | Record a transfer fill |
| `CommandBuffer.copy_buffer(command, src, dst, regions)` | Record nonempty byte ranges from `List<BufferCopy>` |
| `CommandBuffer.pipeline_barrier(command, src_stage, dst_stage, memory, buffers, images)` | Record explicit memory, buffer and image barriers |
| `CommandBuffer.end(command)` | End recording |
| `Device.create_fence(device, signaled)` | A caller-owned fence |
| `Device.submit(device, command, fence)` | Submit one executable command with an unsignaled same-device fence |
| `Fence.status(fence)` | U32 `VK_SUCCESS` or `VK_NOT_READY` |
| `Fence.wait(fence, timeout_ns)` | U32 `VK_SUCCESS` or `VK_TIMEOUT`, with a full U64 nanosecond timeout |
| `Fence.reset(fence)` | Reset an unassociated fence |
| `Device.destroy_fence(device, fence)` | Destroy an unassociated caller-owned fence |
| `CommandBuffer.reset(command)` | Reset a nonpending command and release recorded references after success |
| `Device.submit_and_wait(device, command)` | The same submission/completion core with a persistent private fence and infinite wait |
| `Device.destroy_command_pool(device, pool)` | Pool teardown and invalidation of its command buffers |

`Fence.wait`, `Device.submit_and_wait`, `Device.wait_idle`, and waits during scoped cleanup or shutdown run synchronously on the IO event loop.
These waits block other IO effects until they return. A finite `Fence.wait` timeout bounds that call's blocking.

`begin` records with `ONE_TIME_SUBMIT`. Commands have Initial, Recording, Executable, Pending, Uncertain, Completed, and Invalid states.
Only Initial commands can begin. Successful individual reset returns a command to Initial, including during recording.
Observed completion makes a one-time command Completed. Reset and re-record before submitting it again.
A failed driver reset makes the command Invalid and retains its references.
Pools enable `RESET_COMMAND_BUFFER`. Whole-pool reset and individual command free are absent.

A fill requires bound memory, `VK_BUFFER_USAGE_TRANSFER_DST_BIT`, four-byte alignment, and a nonempty valid range.
Copies require bound buffers, source/destination transfer usages, and positive in-bounds ranges.
They reject overlapping destinations and physical source/destination overlap across every region, including distinct buffers sharing an allocation.
Byte copies impose no four-byte alignment rule.
Recorded references are deduplicated and survive completion and recording/reset failures.
Successful command reset or pool destruction releases them. Referenced buffers, images, and framebuffers cannot be destroyed before that release.

Barrier arguments and every new reference node are validated and allocated before recording.
Buffer barriers use `VK_QUEUE_FAMILY_IGNORED` for both family indices. Ownership transfers are absent.
Stage/access validation accepts supported core Vulkan 1.0 bits. Optional geometry and tessellation features remain disabled.
`ALL_COMMANDS` excludes HOST. The fill caller records its transfer-to-host barrier explicitly.
The selected queue must support transfers. There is one selected graphics queue and at most one Pending or Uncertain command per device. The optional presentation profile adds a present queue with separate completion tracking.

Pending/Uncertain commands reject command reset, affected pool destruction, associated fence reset/destruction, and further submission.
Protection remains deterministic until a caller observes completion, even if the GPU has already finished.
Host access rejects entire allocations reached through active references and bindings, including aliases.
The transitive framebuffer path is command to framebuffer to view to image to memory.
Framebuffers retain their pass and views. Views retain images. Bound images retain allocations after command reset.
Completion releases host exclusion but retains all recorded references until successful reset or pool destruction.
Unrelated allocations remain usable. No destructor or mapping operation polls for completion.

Graphics fence SUCCESS and successful device idle complete Pending graphics work. TIMEOUT, NOT_READY, and ordinary wait errors preserve protection.
Known submission OOM leaves command and fence unchanged. Other submit errors enter Uncertain.
Uncertain fence status/wait rejects with `BV_LIFETIME`. Successful idle recovery makes that command Invalid without claiming execution succeeded.
Device loss is sticky, returns exact `VK_ERROR_DEVICE_LOST` bits, invalidates commands, detaches command fence associations, and permits ordered destruction.
The convenience fence is private, lazily allocated once per device, and destroyed at device teardown.
Fabricated public fence keys cannot reset, destroy, or submit that private fence.

`Entry.close` observes graphics and presentation completion, then destroys child objects in dependency order.
It releases Vulkan surfaces before their native windows and unloads the loader last.
If waiting returns an error other than device loss, cleanup leaves the remaining entry tree live for an explicit retry.
Repeated explicit destruction returns an invalid-handle error.

## Development operations

`debug_live_objects()` returns the live native-registry row count.
`debug_u64_roundtrip(value)` returns two limbs after conversion through a native `uint64_t`.
`Device.buffer_requirements_raw`, `Device.image_requirements_raw`, `Instance.image_format_properties_raw`, `Instance.memory_types_raw`, `Instance.memory_heaps_raw`, and `Instance.limits_raw` are FFI adapters used by the public queries.
`LimitsWords()` names the nested raw limb tuple. Applications use `PhysicalDeviceLimits`.

## Native presentation

The [X11 presentation contract](presentation.md) specifies the optional maintenance1 profile, checked window and surface operations, swapchains, borrowed images, binary semaphores, acquisition outcomes, presentation fences, and recreation.
`Device.create_presentation_device` supplements the existing device constructor.
`Device.submit_synced` supplements the existing fence submission with wait/stage and signal lists.
Headless device creation and submission remain available without X11 runtime dependencies.
