import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W

def choose(value: Maybe<U32>, message: String) -> V.Action(U32):
  match value:
    case None{}:
      IO.pure(V.VkResult(U32), Fail{(1, message)})
    case Some{index}:
      V.Action.pure(U32, index)

def first(devices: List<V.PhysicalDevice>) -> V.Action(V.PhysicalDevice):
  match devices:
    case Nil{}:
      IO.pure(V.VkResult(V.PhysicalDevice), Fail{(1, "No Vulkan physical device")})
    case Con{device, rest}:
      V.Action.pure(V.PhysicalDevice, device)

def bytes_equal(left: List<U32>, right: List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case Con{a, xs} Con{b, ys}:
      Bool.and(U32.is_eq(a, b), bytes_equal(xs, ys))
    case _ _:
      False{}

def require(ok: Bool, message: String) -> V.Action(Unit):
  match ok:
    case True{}:
      V.Action.pure(Unit, Unit{})
    case False{}:
      IO.pure(V.VkResult(Unit), Fail{(1, message)})

def roundtrip(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +buffer: V.Buffer, requirements: V.MemoryRequirements) -> V.Action(Unit):
  V.MemoryRequirements{size, alignment, bits} = requirements
  do V.Action<Unit>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance, physical)
    index : U32 <- choose(Core.find_memory_type(types, bits, vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT()), "No host-visible buffer memory type")
    +memory : V.DeviceMemory <- V.Device.allocate_memory(device, size, index)
    V.Device.bind_buffer_memory(device, buffer, memory, W.zero())
    V.Device.write_memory(device, memory, W.zero(), [0, 127, 255, 17])
    host : List<U32> <- V.Device.read_memory(device, memory, W.zero(), 4)
    require(bytes_equal(host, [0, 127, 255, 17]), "Host memory readback mismatch")
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device, pool)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.fill_buffer(command, buffer, W.zero(), W.of_u32(16), 707406378)
    V.CommandBuffer.pipeline_barrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT(), vk.VK_PIPELINE_STAGE_HOST_BIT(), [V.MemoryBarrier{vk.VK_ACCESS_TRANSFER_WRITE_BIT(), vk.VK_ACCESS_HOST_READ_BIT()}], [])
    V.CommandBuffer.end(command)
    V.Device.submit_and_wait(device, command)
    gpu : List<U32> <- V.Device.read_memory(device, memory, W.zero(), 16)
    require(bytes_equal(gpu, [42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42]), "GPU fill readback mismatch")
    V.Device.destroy_command_pool(device, pool)
    V.Device.destroy_buffer(device, buffer)
    V.Device.free_memory(device, memory)
    V.Device.destroy(device)
    V.Instance.destroy(instance)
    V.Action.lift(Unit, IO.print("Host roundtrip and GPU buffer fill verified"))

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance, physical)
    family : U32 <- choose(Core.find_queue_family(families, vk.VK_QUEUE_GRAPHICS_BIT()), "No graphics queue family")
    +device : V.Device <- V.Instance.create_device(instance, physical, V.DeviceCreateInfo{family, []})
    +buffer : V.Buffer <- V.Device.create_buffer(device, V.BufferCreateInfo{W.of_u32(16), vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT()})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device, buffer)
    roundtrip(instance, physical, device, buffer, requirements)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit, entry => run(entry))
    V.or_exit(Unit, result)
