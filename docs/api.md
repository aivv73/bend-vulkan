# API reference

The public module is `Vulkan.bend`. Vulkan constants are zero-argument definitions in `src/constants.bend`, with their original `VK_` names.
`src/core.bend` provides API-version encoding, flag predicates, queue-family selection, memory-type selection, and U64 limb conversion.

Every native operation returns `IO(VkResult(A))`. `VkResult(A)` is `Result<&1, &1, (U32 & String), A>`.
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
| `Entry.create_instance(entry, info)` | An instance |
| `Entry.close(entry)` | Cascading resource teardown and library unload |
| `Instance.enumerate_physical_devices(instance)` | A list of physical devices |
| `Instance.get_physical_device_properties(instance, physical)` | Name, API version, driver version, vendor ID, device ID, and type |
| `Instance.get_physical_device_queue_family_properties(instance, physical)` | A list of `(flags, queue_count)` pairs indexed by family |
| `Instance.get_physical_device_memory_properties(instance, physical)` | A list of `Core.MemoryType{property_flags, heap_index}` indexed by memory type |
| `Instance.create_device(instance, physical, info)` | A device with one queue at priority 1.0 |
| `Instance.destroy(instance)` | Instance teardown, rejecting live devices |

`InstanceCreateInfo{application_name, api_version, layers, extensions}` accepts explicit layer and extension names.
`InstanceCreateInfo.default()` requests Vulkan 1.0, with no layers or extensions.
`DeviceCreateInfo{queue_family_index, extensions}` selects one queue and enables no optional device features.
Strings containing NUL are rejected. Allocation callbacks are null.
Physical devices are interned within an instance and invalidated when the instance is destroyed.
The memory query currently exposes memory types, without heap sizes or device limits.

## Buffers and memory

| Operation | Result |
| --- | --- |
| `Device.create_buffer(device, BufferCreateInfo{size, usage})` | An exclusive, non-sparse buffer |
| `Device.get_buffer_memory_requirements(device, buffer)` | `MemoryRequirements{size, alignment, memory_type_bits}` |
| `Device.allocate_memory(device, size, memory_type_index)` | An allocation |
| `Device.bind_buffer_memory(device, buffer, memory, offset)` | A binding after size, alignment, type, and owner checks |
| `Device.write_memory(device, memory, offset, bytes)` | Checked host write, including flush for noncoherent memory |
| `Device.read_memory(device, memory, offset, count)` | Byte list, including invalidation for noncoherent memory |
| `Device.destroy_buffer(device, buffer)` | Buffer teardown |
| `Device.free_memory(device, memory)` | Allocation teardown, rejecting bound buffers |
| `Device.wait_idle(device)` | Device completion |
| `Device.destroy(device)` | Device teardown, rejecting live resources |

Sizes, offsets, and alignments are `bend-collections` `W.U64` values.
`Core.whole_size()` returns Vulkan's all-ones `VK_WHOLE_SIZE` value.
`Core.find_memory_type(types, memory_type_bits, required_flags)` returns the first eligible index or `None`.
`Core.find_queue_family(families, required_flags)` skips empty queues and returns the first matching family.

A byte list contains U32 values from 0 through 255. Copies require host-visible memory.
Each read or write maps the whole allocation temporarily and copies a checked subrange.
`read_memory` takes a U32 byte count. Both copy operations are limited to 16 MiB per call.
Memory allocation sizes and copy offsets retain all 64 bits.

The wrapper checks common lifetime and memory-access errors. Callers remain responsible for Vulkan validity requirements for chosen flags, extensions, and resource use.
Handle keys are checked process-local identifiers. They provide no raw Vulkan handle interoperation or access-control guarantee.

## Command submission

| Operation | Result |
| --- | --- |
| `Device.create_command_pool(device)` | A pool for the device's selected queue family |
| `Device.allocate_command_buffer(device, pool)` | One primary command buffer |
| `CommandBuffer.begin(command)` | Begin one-time recording |
| `CommandBuffer.fill_buffer(command, buffer, offset, size, data)` | Record a transfer fill |
| `CommandBuffer.end(command)` | Record a transfer-write-to-host-read barrier, then end recording |
| `Device.submit_and_wait(device, command)` | Queue submission followed by `vkQueueWaitIdle` |
| `Device.destroy_command_pool(device, pool)` | Pool teardown and invalidation of its command buffers |

Command buffers are one-shot. They progress through initial, recording, executable, and submitted states.
Failed recording moves a command buffer to an invalid state. Destroy its pool to release it.
A fill requires bound memory, `VK_BUFFER_USAGE_TRANSFER_DST_BIT`, four-byte alignment, and a nonempty valid range.
Recorded buffer references remain live until their command pool is destroyed.
The selected queue family must support transfer commands. The examples use a graphics queue.
The API has no asynchronous submission, command reset, individual command-buffer free, or semaphore operations.
If submission or a queue wait fails without device loss, memory copies, resource destruction, and further submissions require a successful `Device.wait_idle` first.

`Entry.close` waits for devices, destroys pools and buffers, frees allocations, destroys devices and instances, and unloads the library.
If waiting returns an error other than device loss, cleanup leaves the remaining entry tree live for an explicit retry.
Repeated explicit destruction returns an invalid-handle error.

## Development operations

`debug_live_objects()` returns the live native-registry row count.
`debug_u64_roundtrip(value)` returns two limbs after conversion through a native `uint64_t`.
`Device.buffer_requirements_raw` and `Instance.memory_types_raw` are FFI adapters used by the public query operations.
