# Bend Vulkan dispatch and ownership

Bend 2.0.37 accepts custom IO effects but cannot extend its opaque host-handle types.
Ordinary constructors can cross the FFI, and callers can construct those values themselves.
The wrapper therefore keeps Vulkan pointers and dispatch tables in C and exposes checked identifiers in distinct Bend handle types.

## Caller's view

The allocation sequence remains explicit: create a buffer, query its requirements, select a compatible memory type, allocate memory, and bind it.
The public API also exposes command pools, command buffers, and submission.
`examples/buffer_roundtrip.bend` is the executable usage specification.
The `Action` monad propagates returned failures to `Entry.with`, which performs dependency-ordered cleanup.

## Native ownership

Each registry row has a kind, parent, and process-wide monotonic U32 key.
Keys never repeat, even after destruction or an unsuccessful operation. Exhausting the key space fails allocation.
These keys are registry identifiers, separate from Vulkan's native handle representation.
All Vulkan byte sizes and offsets use upstream `bend-collections` U64.

An Entry owns `dlopen` and global functions obtained through `vkGetInstanceProcAddr`.
An Instance owns instance functions obtained with its `VkInstance`.
A Device owns device functions obtained through `vkGetDeviceProcAddr`.
Parent rows outlive children. Buffer bindings and recorded command references add the dependencies required for destruction checks.
Physical-device rows are borrowed from their instance and interned across repeated enumeration.

All registry mutations and Vulkan effects run on Bend's IO event loop.
The initial submission API waits before returning. It introduces no shared writer across Bend parallel evaluation or helper threads.
Pure preparation can use Bend parallel calls. Dependent Vulkan state transitions remain sequenced through IO.

## FFI representation

The installed compiler emits packed constructors for single U32 handles and flattens the two limbs inside `BufferCreateInfo`.
The native boundary follows those emitted layouts rather than treating every constructor as a boxed object.
Imported constructor aliases cannot appear in this compiler's `CID` macros.
Native outputs that contain U64 values therefore cross as limb tuples, and pure Bend adapters reconstruct the dependency's actual U64.
No second U64 arithmetic implementation is present.

The effect ABI is internal to Bend. The native registrations use the two-argument `io_eff` emitted by Bend 2.0.37.
The integration tests exercise packed handles, the flattened buffer config, all U64 limbs, strings, lists, nested tuples, and result values.
Changing compiler versions requires rebuilding and rerunning those checks.

## Synthesis decision

Three independent designs compared affine owners, Data references, explicit mapped views, and temporary copy-based mapping.
All proposed native ownership checks. The selected base was candidate 3's Data references, entry scope, and copy-based mapping.
Candidate 2 contributed physical-device interning and strict stale-key errors. Candidate 1 contributed dependency-aware cleanup and completion checks.
An independent cross-judge also selected candidate 3 and approved monotonic U32 registry keys and the U64 limb adapter.

The implementation adds reusable command recording and synchronous GPU fill submission to the initial discovery and allocation subset.
The GPU example verifies driver execution, while `tests/native.bend` checks invalid inputs and successful and failed scope cleanup.

Raw pointer-valued handles would allow fabricated constructors to reach driver pointers.
Affine wrappers alone would still allow drops without native destruction and would require threading owners through every result.
Explicit mapped views would add pointer and cache lifetime states to the first API.
The chosen copy operations hide those states while preserving explicit Vulkan allocation choices.

The costs are registry lookup overhead, copied host byte lists, a synchronous queue, and a limited initial API.
Native handle adoption, full Vulkan registry generation, graphics, compute pipelines, and platform integration remain outside this implementation.
