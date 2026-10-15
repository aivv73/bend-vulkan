import Base
import ./src/core.bend as Core
import ./deps/bend-collections/src/math/u64.bend as W

# Handles carry checked registry keys, never native pointers.
type Entry is Data:
  Entry{key: U32}
type Instance is Data:
  Instance{key: U32}
type PhysicalDevice is Data:
  PhysicalDevice{key: U32}
type Device is Data:
  Device{key: U32}
type Buffer is Data:
  Buffer{key: U32}
type DeviceMemory is Data:
  DeviceMemory{key: U32}
type CommandPool is Data:
  CommandPool{key: U32}
type CommandBuffer is Data:
  CommandBuffer{key: U32}

type Fence is Data:
  Fence{key: U32}

type BufferCopy is Data:
  BufferCopy{src_offset: W.U64, dst_offset: W.U64, size: W.U64}

type MemoryBarrier is Data:
  MemoryBarrier{src_access: U32, dst_access: U32}
type BufferMemoryBarrier is Data:
  BufferMemoryBarrier{buffer: Buffer, offset: W.U64, size: W.U64, src_access: U32, dst_access: U32}

type InstanceCreateInfo is Type:
  InstanceCreateInfo{application_name: String, api_version: U32, layers: List<String>, extensions: List<String>}

def InstanceCreateInfo.default() -> InstanceCreateInfo:
  InstanceCreateInfo{"Bend Vulkan", Core.make_api_version(0, 1, 0, 0), [], []}

type DeviceCreateInfo is Type:
  DeviceCreateInfo{queue_family_index: U32, extensions: List<String>}

type BufferCreateInfo is Data:
  BufferCreateInfo{size: W.U64, usage: U32}

type PhysicalDeviceProperties is Data:
  PhysicalDeviceProperties{device_name: String, api_version: U32, driver_version: U32, vendor_id: U32, device_id: U32, device_type: U32}

type MemoryRequirements is Data:
  MemoryRequirements{size: W.U64, alignment: W.U64, memory_type_bits: U32}

# Negative VkResult values retain their exact two's-complement U32 bits.
# Wrapper failures occupy 0x60000000..0x600000ff and include a message.
def VkResult(-A: Type) -> Type:
  Result<&1, &1, (U32 & String), A>

def or_exit(-A: Type, result: VkResult(A)) -> IO(A):
  match result:
    case Done{value}:
      IO.pure(A, value)
    case Fail{(code, message)}:
      IO.die(A, 1, "Vulkan error " ++ U32.show(code) ++ ": " ++ message)

# A Result-returning IO monad: Fail skips the remaining actions, then Entry.with cleans up.
def Action(-A: Type) -> Type:
  IO(VkResult(A))

def Action.pure(-A: Type, value: A) -> Action(A):
  IO.pure(VkResult(A), Done{value})

def Action.next(-A: Type, -B: Type, next: A -> Action(B), result: VkResult(A)) -> Action(B):
  match result:
    case Done{value}:
      next(value)
    case Fail{error}:
      IO.pure(VkResult(B), Fail{error})

def Action.bind(-A: Type, -B: Type, action: Action(A), next: A -> Action(B)) -> Action(B):
  IO.bind(VkResult(A), VkResult(B), action, Action.next(A, B, next))

def Action.lift(-A: Type, action: IO(A)) -> Action(A):
  IO.bind(A, VkResult(A), action, value => IO.pure(VkResult(A), Done{value}))

# BEGIN GENERATED EFFECTS
def Entry.load() -> IO(VkResult(Entry)):
  import "./src/native.c"
  import "./src/native.js"

def Entry.close(entry: Entry) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Entry.enumerate_instance_version(entry: Entry) -> IO(VkResult(U32)):
  import "./src/native.c"
  import "./src/native.js"

def Entry.create_instance(entry: Entry, info: InstanceCreateInfo) -> IO(VkResult(Instance)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.destroy(instance: Instance) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.enumerate_physical_devices(instance: Instance) -> IO(VkResult(List<PhysicalDevice>)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.get_physical_device_properties(instance: Instance, physical: PhysicalDevice) -> IO(VkResult(PhysicalDeviceProperties)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.get_physical_device_queue_family_properties(instance: Instance, physical: PhysicalDevice) -> IO(VkResult(List<(U32 & U32)>)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.memory_types_raw(instance: Instance, physical: PhysicalDevice) -> IO(VkResult(List<(U32 & U32)>)):
  import "./src/native.c"
  import "./src/native.js"

def Instance.create_device(instance: Instance, physical: PhysicalDevice, info: DeviceCreateInfo) -> IO(VkResult(Device)):
  import "./src/native.c"
  import "./src/native.js"

def Device.destroy(device: Device) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.wait_idle(device: Device) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.create_buffer(device: Device, info: BufferCreateInfo) -> IO(VkResult(Buffer)):
  import "./src/native.c"
  import "./src/native.js"

def Device.destroy_buffer(device: Device, buffer: Buffer) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.buffer_requirements_raw(device: Device, buffer: Buffer) -> IO(VkResult(((U32 & U32) & ((U32 & U32) & U32)))):
  import "./src/native.c"
  import "./src/native.js"

def Device.allocate_memory(device: Device, size: W.U64, memory_type_index: U32) -> IO(VkResult(DeviceMemory)):
  import "./src/native.c"
  import "./src/native.js"

def Device.free_memory(device: Device, memory: DeviceMemory) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.bind_buffer_memory(device: Device, buffer: Buffer, memory: DeviceMemory, offset: W.U64) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.write_memory(device: Device, memory: DeviceMemory, offset: W.U64, bytes: List<U32>) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.write_memory_words(device: Device, memory: DeviceMemory, offset: W.U64, byte_length: W.U64, words: Array<U32>) -> IO(Array<U32> & VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.read_memory(device: Device, memory: DeviceMemory, offset: W.U64, count: U32) -> IO(VkResult(List<U32>)):
  import "./src/native.c"
  import "./src/native.js"

def Device.create_command_pool(device: Device) -> IO(VkResult(CommandPool)):
  import "./src/native.c"
  import "./src/native.js"

def Device.destroy_command_pool(device: Device, pool: CommandPool) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.allocate_command_buffer(device: Device, pool: CommandPool) -> IO(VkResult(CommandBuffer)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.begin(command: CommandBuffer) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.fill_buffer(command: CommandBuffer, buffer: Buffer, offset: W.U64, size: W.U64, data: U32) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.copy_buffer(command: CommandBuffer, src: Buffer, dst: Buffer, regions: List<BufferCopy>) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.pipeline_barrier(command: CommandBuffer, src_stage: U32, dst_stage: U32, memory: List<MemoryBarrier>, buffers: List<BufferMemoryBarrier>) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.end(command: CommandBuffer) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.submit_and_wait(device: Device, command: CommandBuffer) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def debug_live_objects() -> IO(VkResult(U32)):
  import "./src/native.c"
  import "./src/native.js"

def debug_u64_roundtrip(value: W.U64) -> IO(VkResult((U32 & U32))):
  import "./src/native.c"
  import "./src/native.js"

def Device.create_fence(device: Device, signaled: Bool) -> IO(VkResult(Fence)):
  import "./src/native.c"
  import "./src/native.js"

def Device.destroy_fence(device: Device, fence: Fence) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Device.submit(device: Device, command: CommandBuffer, fence: Fence) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def Fence.status(fence: Fence) -> IO(VkResult(U32)):
  import "./src/native.c"
  import "./src/native.js"

def Fence.wait(fence: Fence, timeout_ns: W.U64) -> IO(VkResult(U32)):
  import "./src/native.c"
  import "./src/native.js"

def Fence.reset(fence: Fence) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"

def CommandBuffer.reset(command: CommandBuffer) -> IO(VkResult(Unit)):
  import "./src/native.c"
  import "./src/native.js"
# END GENERATED EFFECTS

def requirements_from_words(words: (U32 & U32) & ((U32 & U32) & U32)) -> MemoryRequirements:
  (size, (alignment, bits)) = words
  MemoryRequirements{Core.size_from_words(size), Core.size_from_words(alignment), bits}

def requirements_result(result: VkResult(((U32 & U32) & ((U32 & U32) & U32)))) -> VkResult(MemoryRequirements):
  match result:
    case Fail{error}:
      Fail{error}
    case Done{words}:
      Done{requirements_from_words(words)}

def Device.get_buffer_memory_requirements(device: Device, buffer: Buffer) -> IO(VkResult(MemoryRequirements)):
  do IO<VkResult(MemoryRequirements)>:
    result : VkResult(((U32 & U32) & ((U32 & U32) & U32))) <- Device.buffer_requirements_raw(device, buffer)
    return requirements_result(result)

def memory_types_from_words(words: List<(U32 & U32)>) -> List<Core.MemoryType>:
  match words:
    case Nil{}:
      Nil{}
    case Con{(flags, heap), rest}:
      Core.MemoryType{flags, heap} <> memory_types_from_words(rest)

def memory_types_result(result: VkResult(List<(U32 & U32)>)) -> VkResult(List<Core.MemoryType>):
  match result:
    case Fail{error}:
      Fail{error}
    case Done{words}:
      Done{memory_types_from_words(words)}

def Instance.get_physical_device_memory_properties(instance: Instance, physical: PhysicalDevice) -> IO(VkResult(List<Core.MemoryType>)):
  do IO<VkResult(List<Core.MemoryType>)>:
    result : VkResult(List<(U32 & U32)>) <- Instance.memory_types_raw(instance, physical)
    return memory_types_result(result)

def Entry.finish(-A: Type, result: VkResult(A), cleanup: VkResult(Unit)) -> VkResult(A):
  match result cleanup:
    case Fail{(code, message)} Fail{(cleanup_code, cleanup_message)}:
      Fail{(code, message ++ "; cleanup error " ++ U32.show(cleanup_code) ++ ": " ++ cleanup_message)}
    case Fail{error} Done{unit}:
      Fail{error}
    case Done{value} Done{unit}:
      Done{value}
    case Done{value} Fail{error}:
      Fail{error}

def Entry.run_loaded(-A: Type, body: Entry -> IO(VkResult(A)), loaded: VkResult(Entry)) -> IO(VkResult(A)):
  match loaded:
    case Fail{error}:
      IO.pure(VkResult(A), Fail{error})
    case Done{+entry}:
      do IO<VkResult(A)>:
        result : VkResult(A) <- body(entry)
        cleanup : VkResult(Unit) <- Entry.close(entry)
        return Entry.finish(A, result, cleanup)

def Entry.with(-A: Type, body: Entry -> IO(VkResult(A))) -> IO(VkResult(A)):
  do IO<VkResult(A)>:
    loaded : VkResult(Entry) <- Entry.load()
    Entry.run_loaded(A, body, loaded)
