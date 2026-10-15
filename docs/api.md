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
| `Instance.get_physical_device_limits(instance, physical)` | The selected `PhysicalDeviceLimits` fields |
| `Instance.create_device(instance, physical, info)` | A device with one queue at priority 1.0 |
| `Instance.destroy(instance)` | Instance teardown, rejecting live devices |

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

Its final three fields are upstream W.U64 values, `non_coherent_atom_size`, `optimal_buffer_copy_offset_alignment`, and `optimal_buffer_copy_row_pitch_alignment`.
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
| `Device.free_memory(device, memory)` | Allocation teardown, rejecting bound buffers |
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

## Command submission

| Operation | Result |
| --- | --- |
| `Device.create_command_pool(device)` | A pool for the device's selected queue family |
| `Device.allocate_command_buffer(device, pool)` | One primary command buffer |
| `CommandBuffer.begin(command)` | Begin one-time recording |
| `CommandBuffer.fill_buffer(command, buffer, offset, size, data)` | Record a transfer fill |
| `CommandBuffer.copy_buffer(command, src, dst, regions)` | Record nonempty byte ranges from `List<BufferCopy>` |
| `CommandBuffer.pipeline_barrier(command, src_stage, dst_stage, memory, buffers)` | Record explicit memory and buffer barriers |
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
Successful command reset or pool destruction releases them. Referenced buffers cannot be destroyed before that release.

Barrier arguments and every new reference node are validated and allocated before recording.
Buffer barriers use `VK_QUEUE_FAMILY_IGNORED` for both family indices. Ownership transfers are absent.
Stage/access validation accepts supported core Vulkan 1.0 bits. Optional geometry and tessellation features remain disabled.
`ALL_COMMANDS` excludes HOST. The fill caller records its transfer-to-host barrier explicitly.
The selected queue must support transfers. There is one selected queue and at most one Pending or Uncertain command per device.

Pending/Uncertain commands reject command reset, affected pool destruction, associated fence reset/destruction, and further submission.
Protection remains deterministic until a caller observes completion, even if the GPU has already finished.
Host access rejects entire allocations reached through active references and buffer bindings, including aliases.
Unrelated allocations remain usable. No destructor or mapping operation polls for completion.

Fence SUCCESS and successful device idle complete Pending work. TIMEOUT, NOT_READY, and ordinary wait errors preserve protection.
Known submission OOM leaves command and fence unchanged. Other submit errors enter Uncertain.
Uncertain fence status/wait rejects with `BV_LIFETIME`. Successful idle recovery makes that command Invalid without claiming execution succeeded.
Device loss is sticky, returns exact `VK_ERROR_DEVICE_LOST` bits, invalidates commands, detaches associations, and permits ordered destruction.
The convenience fence is private, lazily allocated once per device, and destroyed at device teardown.
Fabricated public fence keys cannot reset, destroy, or submit that private fence.

`Entry.close` waits for devices, destroys pools, fences, and buffers, frees allocations, destroys devices and instances, and unloads the library.
If waiting returns an error other than device loss, cleanup leaves the remaining entry tree live for an explicit retry.
Repeated explicit destruction returns an invalid-handle error.

## Development operations

`debug_live_objects()` returns the live native-registry row count.
`debug_u64_roundtrip(value)` returns two limbs after conversion through a native `uint64_t`.
`Device.buffer_requirements_raw`, `Instance.memory_types_raw`, `Instance.memory_heaps_raw`, and `Instance.limits_raw` are FFI adapters used by the public queries.
`LimitsWords()` names the nested raw limb tuple. Applications use `PhysicalDeviceLimits`.
