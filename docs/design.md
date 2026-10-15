# Bend Vulkan dispatch and ownership

Bend 2.0.37 cannot extend its opaque host-handle types. Ordinary Data constructors are copyable and forgeable.
The wrapper keeps native handles and dispatch in C and exposes distinct checked U32 registry keys.
`Entry.with` closes the resource tree after a callback returns either success or failure.
Allocation, binding, stage/access masks, timeouts, and reset remain explicit caller choices.

## Registry and dependencies

An Entry owns the loader library and global dispatch. An Instance owns instance dispatch and interned physical-device rows.
A Device owns device dispatch, one selected queue, and its resources. Pools own command buffers.
Buffers retain their bound allocations. Commands retain generic, deduplicated references to recorded resources.
Keys are monotonic and never reused, including after failed creation. Native pointers never come from public keys.
Every effect and registry mutation runs on Bend's IO event loop. Pure preparation can run in parallel.
Dependent Vulkan effects remain sequenced because they mutate the same queue and resource tree.

Recording validates every argument and reserves all reference nodes and marshaling arrays before any void `vkCmd*` dispatch.
Fill retains its buffer. Copy retains both buffers. Buffer barriers retain each mentioned buffer.
References survive completion and failed recording/reset. Successful individual reset or pool destruction releases them.
This keeps buffer destruction independent of whether hardware has finished but completion remains unobserved.
Copy overlap checks use allocation identity plus buffer binding offsets across all source/destination regions.

## Command-owned completion

The command has one tagged state:

| State | Meaning |
| --- | --- |
| Initial | Can begin recording |
| Recording | Can record and end |
| Executable | Can submit |
| Pending with a fence | Vulkan accepted the submission; completion is unobserved |
| Uncertain with a fence | An unexpected submit error requires idle recovery |
| Completed | Completion was observed for this one-time recording |
| Invalid | Reset is required before another recording |

`begin` preserves `ONE_TIME_SUBMIT`. A Completed command cannot resubmit.
Successful reset returns any nonactive command to Initial and clears references. Failed reset invalidates the command and retains references.
Pools enable individual command reset. There is no public whole-pool reset or usage mode.

The command union is the sole submission association. Registry scans find a device's active command or a fence's association.
The device has Healthy/Lost health and a private convenience-fence cache. A fence has a native handle and caller/private lifetime.
There is no device pending flag, fence backpointer, cached signal bit, or second submission registry.
One selected queue and at most one Pending or Uncertain command keep these linear scans bounded by the live registry.

Fence SUCCESS and successful device idle use the same completion transition.
Timeouts, NOT_READY, and ordinary errors retain Pending protection. Submit OOM leaves command and fence unchanged.
Unexpected submit errors enter Uncertain. Fence status/wait rejects that state because submission may never have occurred.
Successful idle recovery makes Uncertain work Invalid without claiming execution or readback succeeded.
Device loss is sticky. It invalidates every command, detaches associations, and permits dependency-ordered teardown with exact loss bits.

Host mapping follows active command references through buffer bindings and rejects the entire reached allocation, including aliases.
Unrelated allocations remain usable. Reset, destruction, mapping, and further submit never poll for completion implicitly.
`submit_and_wait` uses the same submit/observe functions with U64_MAX and one lazily allocated persistent private fence per device.
Public fence lookup rejects private rows, including fabricated keys. Only device teardown destroys the cached fence.

## Cleanup and errors

Entry cleanup observes idle first, then destroys pools, fences, buffers, allocations, devices, physical rows, instances, and the loader.
An ordinary idle error leaves unsafe resources and the entry live for explicit retry. Known loss permits teardown and returns exact loss.
A callback failure keeps its original code and appends a cleanup failure's diagnostic.
Explicit device destruction requires public children gone and also destroys its private convenience fence.

Vulkan results retain their exact two's-complement U32 bits. Fence status/wait return ordinary SUCCESS, NOT_READY, or TIMEOUT inside Done.
Wrapper failures have distinct invalid-handle, argument, lifetime, and allocation-limit codes.
Checks cover this subset's native boundary. The application still owns Vulkan synchronization correctness and capability negotiation.

## Compiler ABI and packed uploads

The compiler packs single-U32 handles and flattens nested Data fields in buffer configs, copies, and buffer barriers.
C follows emitted layouts. Imported U64 constructors cannot appear in native CID macros.
Heap sizes and selected limits cross as nested U32 limb tuples. Pure adapters reconstruct the pinned bend-collections U64.
All sizes, offsets, alignments, and nanosecond timeouts use that upstream type. Existing byte-list read counts remain U32.

Packed uploads return `Array<U32> & VkResult(Unit)` on every path. The generator records the owner argument explicitly in its manifest.
Native code reads packed TAG_BUF slots or Term-backed TAG_ARR slots with emitted block helpers and resolves shared blocks.
Capacity is the block's logical word count, rather than its heap span. No Bend heap pointer survives the immediate operation.
Words emit low-order bytes first. An explicit byte length truncates a partial final word and must fit capacity, allocation range, SIZE_MAX, and 16 MiB.
Each operation maps the whole allocation, maintains whole-allocation noncoherent cache ranges when needed, and unmaps every mapped path.
A flush error may leave destination bytes modified while returning the original words unchanged.

## Discovery and scope

Entry dispatch enumerates layers and instance extensions. Instance dispatch queries device extensions, heaps, core-1.0 formats, and thirteen selected limits.
Enumeration accepts empty results, bounds count allocations, and retries VK_INCOMPLETE at most eight times.
Optional layer names pass to Vulkan explicitly. Queries return capabilities without enabling them.
The registry extract retains its original source SHA256 and adds core format, format-feature, and memory-heap constants from that same source.

The fixed compiler version is part of this ABI contract. Real effect-return tests cover native and interpreted array ownership.
Test-only C probes substitute dispatch and metadata allocation in an emitted translation unit. Production code exposes no injection hooks.
Those probes distinguish controlled errors and loss from driver execution.
Separate native runs verify literal GPU readback, 32 changing staging/copy/readback cycles, command/fence reuse, and stable registry rows.
Pure laws cover packing and limb conversion, not driver behavior.

Linear registry scans, allocation-wide host exclusion, and one-time recordings keep one ownership model for this milestone.
Multiple queues, multiple active submissions, images, shaders, graphics, descriptors, and presentation remain outside this subset.
