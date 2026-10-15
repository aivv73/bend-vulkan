import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo

def check_error(-A: Type, expected: U32, result: V.VkResult(A)) -> V.Action(Unit):
  match result:
    case Fail{(+code, message)}:
      Demo.require(U32.is_eq(code, expected), "Wrong error code: " ++ U32.show(code) ++ " / " ++ message)
    case Done{value}:
      IO.pure(V.VkResult(Unit), Fail{(1, "Expected an error; operation succeeded")})

def expect_error(-A: Type, expected: U32, action: V.Action(A)) -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    result : V.VkResult(A) <- action
    check_error(A, expected, result)

def check_words(words: U32 & U32, lo: U32, hi: U32) -> V.Action(Unit):
  (actual_lo, actual_hi) = words
  Demo.require(Bool.and(U32.is_eq(actual_lo, lo), U32.is_eq(actual_hi, hi)), "C U64 boundary lost a limb")

def check_u64() -> V.Action(Unit):
  do V.Action<Unit>:
    zero : U32 & U32 <- V.debug_u64_roundtrip(W.zero())
    check_words(zero, 0, 0)
    high : U32 & U32 <- V.debug_u64_roundtrip(W.U64{0, 1})
    check_words(high, 0, 1)
    mixed : U32 & U32 <- V.debug_u64_roundtrip(W.U64{2309737967, 19088743})
    check_words(mixed, 2309737967, 19088743)
    max : U32 & U32 <- V.debug_u64_roundtrip(Core.whole_size())
    check_words(max, 4294967295, 4294967295)

def buffer_checks(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +buffer: V.Buffer, requirements: V.MemoryRequirements) -> V.Action(Unit):
  V.MemoryRequirements{size, alignment, bits} = requirements
  do V.Action<Unit>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance, physical)
    index : U32 <- Demo.choose(Core.find_memory_type(types, bits, 2), "No host-visible memory")
    +memory : V.DeviceMemory <- V.Device.allocate_memory(device, size, index)
    expect_error(Unit, 1610612739, V.Device.bind_buffer_memory(device, buffer, memory, W.U64{0, 1}))
    V.Device.bind_buffer_memory(device, buffer, memory, W.zero())
    expect_error(Unit, 1610612740, V.Device.bind_buffer_memory(device, buffer, memory, W.zero()))
    expect_error(Unit, 1610612740, V.Device.free_memory(device, memory))
    expect_error(Unit, 1610612740, V.Device.destroy(device))
    expect_error(Unit, 1610612740, V.Instance.destroy(instance))
    expect_error(Unit, 1610612739, V.Device.write_memory(device, memory, W.zero(), [256]))
    expect_error(List<U32>, 1610612739, V.Device.read_memory(device, memory, W.U64{0, 1}, 1))
    expect_error(List<U32>, 1610612739, V.Device.read_memory(device, memory, Core.whole_size(), 2))
    expect_error(List<U32>, 1610612741, V.Device.read_memory(device, memory, W.zero(), 16777217))
    V.Device.write_memory(device, memory, W.zero(), [9, 8, 7, 6])
    bytes : List<U32> <- V.Device.read_memory(device, memory, W.zero(), 4)
    Demo.require(Demo.bytes_equal(bytes, [9, 8, 7, 6]), "Rejected writes altered memory")
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device, pool)
    expect_error(Unit, 1610612740, V.Device.submit_and_wait(device, command))
    expect_error(Unit, 1610612740, V.CommandBuffer.end(command))
    V.CommandBuffer.begin(command)
    expect_error(Unit, 1610612740, V.CommandBuffer.begin(command))
    expect_error(Unit, 1610612739, V.CommandBuffer.fill_buffer(command, buffer, W.of_u32(1), W.of_u32(4), 0))
    expect_error(Unit, 1610612739, V.CommandBuffer.fill_buffer(command, buffer, W.zero(), W.U64{0, 1}, 0))
    expect_error(Unit, 1610612739, V.CommandBuffer.pipeline_barrier(command, 0, 16384, [], []))
    expect_error(Unit, 1610612739, V.CommandBuffer.pipeline_barrier(command, 65536, 65536, [V.MemoryBarrier{8192, 8192}], []))
    expect_error(Unit, 1610612739, V.CommandBuffer.pipeline_barrier(command, 64, 4096, [], []))
    expect_error(Unit, 1610612739, V.CommandBuffer.pipeline_barrier(command, 4096, 16384, [], [V.BufferMemoryBarrier{buffer, W.U64{0,1}, W.of_u32(4), 4096, 8192}]))
    V.CommandBuffer.pipeline_barrier(command, 4096, 4096, [], [V.BufferMemoryBarrier{buffer, W.zero(), Core.whole_size(), 0, 4096}])
    V.CommandBuffer.fill_buffer(command, buffer, W.zero(), Core.whole_size(), 707406378)
    expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, buffer))
    V.CommandBuffer.pipeline_barrier(command, vk.VK_PIPELINE_STAGE_TRANSFER_BIT(), vk.VK_PIPELINE_STAGE_HOST_BIT(), [V.MemoryBarrier{vk.VK_ACCESS_TRANSFER_WRITE_BIT(), vk.VK_ACCESS_HOST_READ_BIT()}], [])
    V.CommandBuffer.end(command)
    V.Device.submit_and_wait(device, command)
    V.Device.wait_idle(device)
    expect_error(Unit, 1610612740, V.Device.submit_and_wait(device, command))
    gpu : List<U32> <- V.Device.read_memory(device, memory, W.zero(), 16)
    Demo.require(Demo.bytes_equal(gpu, [42,42,42,42,42,42,42,42,42,42,42,42,42,42,42,42]), "GPU fill mismatch")
    V.Device.destroy_command_pool(device, pool)
    expect_error(Unit, 1610612738, V.CommandBuffer.begin(command))
    V.Device.destroy_buffer(device, buffer)
    expect_error(Unit, 1610612738, V.Device.destroy_buffer(device, buffer))
    V.Device.free_memory(device, memory)
    expect_error(Unit, 1610612738, V.Device.free_memory(device, memory))
    V.Device.destroy(device)
    expect_error(Unit, 1610612738, V.Device.wait_idle(device))
    V.Instance.destroy(instance)
    expect_error(V.PhysicalDeviceProperties, 1610612738, V.Instance.get_physical_device_properties(instance, physical))

def run_checks(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    expect_error(Unit, 1610612738, V.Device.wait_idle(V.Device{4294967295}))
    expect_error(V.Instance, 4294967289, V.Entry.create_instance(entry, V.InstanceCreateInfo{"test", 4194304, [], ["VK_BEND_missing_extension"]}))
    expect_error(V.Instance, 1610612739, V.Entry.create_instance(entry, V.InstanceCreateInfo{SCon{Chr{0}, SNil{}}, 4194304, [], []}))
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    before : U32 <- V.debug_live_objects()
    again : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    after : U32 <- V.debug_live_objects()
    Demo.require(U32.is_eq(before, after), "Repeated enumeration allocated duplicate handles")
    +other_instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    expect_error(V.PhysicalDeviceProperties, 1610612738, V.Instance.get_physical_device_properties(other_instance, physical))
    V.Instance.destroy(other_instance)
    expect_error(V.Device, 1610612739, V.Instance.create_device(instance, physical, V.DeviceCreateInfo{4294967295, []}))
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance, physical)
    +family : U32 <- Demo.choose(Core.find_queue_family(families, 1), "No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance, physical, V.DeviceCreateInfo{family, []})
    +other : V.Device <- V.Instance.create_device(instance, physical, V.DeviceCreateInfo{family, []})
    +foreign_buffer : V.Buffer <- V.Device.create_buffer(other, V.BufferCreateInfo{W.of_u32(16), 2})
    expect_error(V.MemoryRequirements, 1610612738, V.Device.get_buffer_memory_requirements(device, foreign_buffer))
    V.Device.destroy_buffer(other, foreign_buffer)
    V.Device.destroy(other)
    expect_error(V.Buffer, 1610612739, V.Device.create_buffer(device, V.BufferCreateInfo{W.zero(), 2}))
    +buffer : V.Buffer <- V.Device.create_buffer(device, V.BufferCreateInfo{W.of_u32(16), vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT()})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device, buffer)
    buffer_checks(instance, physical, device, buffer, requirements)

def abandon_resources(+instance: V.Instance, physical: V.PhysicalDevice, +device: V.Device, +buffer: V.Buffer, requirements: V.MemoryRequirements) -> V.Action(Unit):
  V.MemoryRequirements{size, alignment, bits} = requirements
  do V.Action<Unit>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance, physical)
    index : U32 <- Demo.choose(Core.find_memory_type(types, bits, 2), "No host-visible memory")
    +memory : V.DeviceMemory <- V.Device.allocate_memory(device, size, index)
    V.Device.bind_buffer_memory(device, buffer, memory, W.zero())
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device, pool)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.fill_buffer(command, buffer, W.zero(), Core.whole_size(), 0)
    IO.pure(V.VkResult(Unit), Fail{(73, "intentional callback failure")})

# Return a failure with a bound allocation and recorded commands still live.
def abandon_buffer(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance, physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families, 1), "No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance, physical, V.DeviceCreateInfo{family, []})
    +buffer : V.Buffer <- V.Device.create_buffer(device, V.BufferCreateInfo{W.of_u32(16), 2})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device, buffer)
    abandon_resources(instance, physical, device, buffer, requirements)

def all_checks() -> V.Action(Unit):
  do V.Action<Unit>:
    check_u64()
    +entry : V.Entry <- V.Entry.load()
    V.Entry.close(entry)
    expect_error(Unit, 1610612738, V.Entry.close(entry))
    V.Entry.with(Unit, entry => run_checks(entry))
    live : U32 <- V.debug_live_objects()
    Demo.require(U32.is_eq(live, 0), "Success cleanup leaked native objects")
    expect_error(Unit, 73, V.Entry.with(Unit, entry => abandon_buffer(entry)))
    remaining : U32 <- V.debug_live_objects()
    Demo.require(U32.is_eq(remaining, 0), "Failure cleanup leaked native objects")
    V.Action.lift(Unit, IO.print("Native Vulkan checks passed"))

def report(result: V.VkResult(Unit)) -> IO(Unit):
  match result:
    case Done{unit}:
      IO.pure(Unit, Unit{})
    case Fail{(+code, message)}:
      IO.die(Unit, 1, "Vulkan test failed (" ++ U32.show(code) ++ "): " ++ message)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- all_checks()
    report(result)
