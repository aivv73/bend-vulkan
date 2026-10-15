# Bend Vulkan dispatch and ownership

Bend 2.0.37 cannot extend its opaque host-handle types. Ordinary Data constructors are copyable and forgeable.
The wrapper keeps native handles and dispatch in C and exposes distinct checked U32 registry keys.
`Entry.with` closes the resource tree after a callback returns either success or failure.
Allocation, binding, stage/access masks, timeouts, and reset remain explicit caller choices.

## Registry and dependencies

An Entry owns the loader library and global dispatch. An Instance owns instance dispatch and interned physical-device rows.
A Device owns device dispatch, one selected queue, and its resources. Pools own command buffers.
The native registry stores one role-tagged dependency DAG.
Commands retain deduplicated buffer, image, framebuffer, and graphics pipeline roots. Framebuffers retain passes and ordered views, views retain images, and buffers/images retain bound allocations.
Pipelines retain layouts and render passes. Shader modules are creation-only inputs.
Binding edges alone store binding offsets. View image identity and framebuffer pass identity derive from their edges.
Framebuffer attachment order uses pointers into its own view edges. No flattened resource closure or reverse map duplicates the graph.
Keys are monotonic and never reused, including after failed creation. Native pointers never come from public keys.
Every effect and registry mutation runs on Bend's IO event loop. Pure preparation can run in parallel.
Dependent Vulkan effects remain sequenced because they mutate the same queue and resource tree.

Recording validates every argument and reserves all reference nodes and marshaling arrays before any void `vkCmd*` dispatch.
Fill retains its buffer. Copies retain both operands. Barriers retain their mentioned buffers and images. Begin-pass retains only its framebuffer.
References survive completion and failed recording/reset. Successful individual reset or pool destruction releases them.
Incoming dependencies reject destruction even after observed completion. Persistent view/framebuffer/binding edges remain until their owning resource is destroyed.
Copy overlap checks use allocation identity plus buffer binding offsets across all source/destination regions.
Buffer requirements are cached separately from logical size. Images use native requirements, never inferred texel footprints.
One shared binding validator rejects image overlap and mixed buffer/optimal-image granularity-page overlap in either bind order.

## Command-owned completion

The command has one tagged state:

| State | Meaning |
| --- | --- |
| Initial | Can begin recording |
| Recording Outside | Can record transfers/barriers, set graphics state, begin a pass, or end the command |
| Recording Inside with a framebuffer | Can bind graphics state, draw indexed geometry, or end the pass |
| Executable | Can submit |
| Pending with a fence | Vulkan accepted the submission; completion is unobserved |
| Uncertain with a fence | An unexpected submit error requires idle recovery |
| Completed | Completion was observed for this one-time recording |
| Invalid | Reset is required before another recording |

`begin` preserves `ONE_TIME_SUBMIT`. A Completed command cannot resubmit.
Successful reset returns any nonactive command to Initial and clears references. Failed reset invalidates the command and retains references.
The Outside/Inside tag exists only in Recording. Pending and Uncertain retain their existing sole fence association.
Begin-pass allocates all clears and references before dispatch. End-pass allocates nothing.
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

Host mapping follows active dependency edges and rejects the entire reached allocation, including aliases.
The longest path is command to framebuffer to view to image to memory, four edges.
Reachability uses bounded traversal without allocation. This safety query cannot fail because memory allocation fails.
Unrelated allocations remain usable. Reset, destruction, mapping, and further submit never poll for completion implicitly.
`submit_and_wait` uses the same submit/observe functions with U64_MAX and one lazily allocated persistent private fence per device.
Public fence lookup rejects private rows, including fabricated keys. Only device teardown destroys the cached fence.

## Cleanup and errors

Entry cleanup observes idle first, then destroys pools, fences, pipelines, layouts, shaders, framebuffers, views, passes, images/buffers, allocations, devices, physical rows, instances, and the loader.
An ordinary idle error leaves unsafe resources and the entry live for explicit retry. Known loss permits teardown and returns exact loss.
A callback failure keeps its original code and appends a cleanup failure's diagnostic.
Explicit device destruction requires public children gone and also destroys its private convenience fence.

Vulkan results retain their exact two's-complement U32 bits. Fence status/wait return ordinary SUCCESS, NOT_READY, or TIMEOUT inside Done.
Wrapper failures have distinct invalid-handle, argument, lifetime, and allocation-limit codes.
Checks cover this subset's native boundary. The application still owns Vulkan synchronization correctness and capability negotiation.

## Compiler ABI and packed uploads

The compiler packs single-U32 handles and flattens nested Data fields in configs, regions, barriers, render areas, and clear colors.
C follows emitted layouts. Imported U64 constructors cannot appear in native CID macros.
Heap sizes and selected limits cross as nested U32 limb tuples. Pure adapters reconstruct the pinned bend-collections U64.
All sizes, offsets, alignments, and nanosecond timeouts use that upstream type. Existing byte-list read counts remain U32.
`tests/image_abi.bend` sends distinct fields through a native effect using the installed compiler.
It checks mixed float lanes, signed zero, packed DepthClear, ColorClear/UnusedClear, Some/None, lists, and distinct high/low limbs.
Native float extraction uses `f32_unbox`, preserving depth `0.5` as `0x3f000000`. It never numerically casts a float to an integer.
The public handle is `ImageHandle` because Base already declares `Image`.

Packed uploads return `Array<U32> & VkResult(Unit)` on every path. The generator records the owner argument explicitly in its manifest.
Native code reads packed TAG_BUF slots or Term-backed TAG_ARR slots with emitted block helpers and resolves shared blocks.
Capacity is the block's logical word count, rather than its heap span. No Bend heap pointer survives the immediate operation.
Words emit low-order bytes first. An explicit byte length truncates a partial final word and must fit capacity, allocation range, SIZE_MAX, and 16 MiB.
Each operation maps the whole allocation, maintains whole-allocation noncoherent cache ranges when needed, and unmaps every mapped path.
A flush error may leave destination bytes modified while returning the original words unchanged.

## Discovery and scope

Entry dispatch enumerates layers and instance extensions. Instance dispatch queries device extensions, heaps, core-1.0 formats, exact image configurations, and fourteen selected limits.
Enumeration accepts empty results, bounds count allocations, and retries VK_INCOMPLETE at most eight times.
Optional layer names pass to Vulkan explicitly. Queries return capabilities without enabling them.
The registry extract retains its original source SHA256 and adds core format, format-feature, and memory-heap constants from that same source.
The image, attachment, layout, and load/store constants retain that same pinned source provenance.

## Explicit image execution

The image profile is 2D, optimal tiling, one sample, depth one, with explicit mips and array layers.
One native format table defines RGBA8/BGRA8 UNORM/SRGB and D16/D32 depth-only traits.
Configuration queries may discover other core configurations, but creation accepts only this profile.
Vulkan creation remains authoritative for actual footprint and returned errors.

Layouts and initialized contents remain caller assertions at execution time. Recording, reset, submit, and completion update no layout ledger.
Unexpected submission errors preserve host exclusion until idle recovery. That recovery establishes safety for teardown, not execution success or contents.
The caller must overwrite, discard, or recreate before relying on uncertain output.

One legacy barrier operation accepts memory, buffer, and image lists. It checks structural layout, range, usage, and stage/access compatibility.
Vulkan 1.0 render passes keep initial, subpass, and final layouts equal to their attachment-optimal layout.
They have one inline graphics subpass and no explicit dependencies. Callers synchronize before and after passes, including LOAD after prior attachment writes.
There is no hidden transition or command-end barrier.

Buffer-image copy regions use texel row length and image height, independent of memory binding offsets and array capacity.
Checked U64 arithmetic counts the last payload row without trailing padding. Downloads conservatively reject overlapping padded envelopes.
Copies preserve raw bytes and increasing x/y/layer order. sRGB clears convert linear RGB, while sRGB copies preserve encoded storage.
See the [image API contract](api.md#image-commands-and-readback) for format bytes, alignment, strides, and caller depth-upload obligations.

The implementation was informed by Voltra at `8900b07e14b80d3528a3b38cb5b376774441d240` before design.
Its Vulkan 1.3 dynamic rendering, packed color conventions, and U32 memory sizes were not copied into this Vulkan 1.0 API.

## Graphics readiness and retention

Typed graphics descriptions marshal through the measured Bend ABI into one native module.
`tests/graphics_abi.bend` checks the actual emitted 14-lane pipeline description, three-lane layout, F32 viewport, signed base bits, lists, and U64 limbs.
Pipeline creation computes immutable per-binding alignment and first-record requirements.
It reserves all metadata and layout/pass edges before native creation, initializes the output to null, and destroys any nonnull failed pipeline output.
Exact VkResult bits and sticky device loss use the existing error path.

Recording stores its render scope, current pipeline, an ordinal vertex readiness mask, index span, and dynamic/push readiness inline.
It owns no heap state and has no persistent binding ledger. Every pipeline bind requires vertex rebinding and full push initialization.
Index and dynamic state persist through pipeline and pass switches within that recording.
All union transitions clear the whole expanded payload. Failure before void dispatch preserves both readiness and graph roots.
The command DAG separately retains every pipeline and vertex/index buffer ever bound in the recording.
A later binding changes readiness without deleting historical dependencies.
The longest memory path remains command to framebuffer to view to image to memory, four edges.

Alignment uses the memory binding offset plus the command-relative offset modulo the required component/index width.
Adding modulo parts avoids U64 sum overflow and permits a relative offset that compensates for the binding offset.
The wrapper checks the index span, never index contents or effective signed vertex indices.
It checks first-record vertex coverage, while subsequent vertex/instance fetches and shader validity remain caller obligations.
The [graphics API contract](api.md#indexed-graphics-recording) defines these boundaries.

## Executed acceptance

The fixed compiler version is part of this ABI contract. Real effect-return tests cover native and interpreted array ownership.
Test-only C probes substitute dispatch and metadata allocation in an emitted translation unit. Production code exposes no injection hooks.
Those probes distinguish controlled errors and loss from driver execution.
Separate native runs verify literal GPU readback, 32 changing staging/copy/readback cycles, command/fence reuse, and stable registry rows.
Image runs verify every-pixel clears, nonuniform padded two-layer/nonzero-mip transfers, full and partial color/depth pass clears, 32 changing attachment cycles, and resource churn.
Indexed acceptance checks literal RGBA8 and D32 pixels for both draw orders, index widths, negative base vertex, a nonsymmetric camera, winding, clipping, dynamic state, color masks, strips, and changing pushes.
It runs 32 stable command/fence/resource reuses. A separate real submission proves overwritten pipeline/buffer retention and allocation host exclusion.
The framebuffer-only lifetime test prepares layouts in an earlier completed and reset recording, removing direct image roots before the pass submission.
Controlled probes cover timeout/NOT_READY, Uncertain recovery, failed reset retaining the graph, no-dispatch failures, creation rollback, and metadata cleanup.
Wrapper allocation counters supplement zero-row assertions because ASan driver-global leak detection is disabled.
Pure laws cover packing, limb conversion, checked U64 arithmetic, mip dimensions, range wrap, and final copy spans. They do not prove driver behavior.

The GTX 1660 run exposes no host-visible type compatible with optimal color image requirements.
Real pre-observation rejection and staging bytes prove driver behavior. Controlled map dispatch separately proves host access resumes after completion/recovery.
No optimal-image mapped pixel read is claimed. The milestone-3 run uses the available Khronos layer with synchronization validation.

Linear registry scans, allocation-wide host exclusion, and one-time recordings keep one ownership model for this milestone.
Multiple queues, multiple active submissions, descriptors, and presentation remain outside this subset.
