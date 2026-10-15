import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./array_rejection.bend as A
import ./native.bend as T

def upload(+device: V.Device, +memory: V.DeviceMemory, offset: W.U64, length: W.U64, expected: U32) -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    owned : Array<U32> & V.VkResult(Unit) <- V.Device.write_memory_words(device, memory, offset, length, A.words())
    A.check_owned(owned, expected)

def allocate(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, requirements: V.MemoryRequirements, required: U32) -> V.Action(V.DeviceMemory):
  V.MemoryRequirements{size, alignment, bits} = requirements
  do V.Action<V.DeviceMemory>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance, physical)
    index : U32 <- Demo.choose(Core.find_memory_type(types, bits, required), "No compatible memory type")
    V.Device.allocate_memory(device, size, index)

def buffer(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, usage: U32, required: U32) -> V.Action(V.Buffer & V.DeviceMemory):
  do V.Action<V.Buffer & V.DeviceMemory>:
    +buffer : V.Buffer <- V.Device.create_buffer(device, V.BufferCreateInfo{W.of_u32(64), usage})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device, buffer)
    +memory : V.DeviceMemory <- allocate(instance, physical, device, requirements, required)
    V.Device.bind_buffer_memory(device, buffer, memory, W.zero())
    return (buffer, memory)

def shared_upload(+device: V.Device, +memory: V.DeviceMemory, pair: Array<U32> & Array<U32>) -> V.Action(Unit):
  (words, original) = pair
  do V.Action<Unit>:
    owned : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit), V.Device.write_memory_words(device,memory,W.zero(),W.of_u32(7),words))
    A.check_owned(owned,0)
    Demo.require(Demo.bytes_equal(Array.to_list(~U32,original),[16909060,134678021,202050057,269422093]),"Shared original changed")

def transfer_body(+device: V.Device, source: V.Buffer & V.DeviceMemory, destination: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  (+src, +source_memory) = source
  (+dst, +dest_memory) = destination
  do V.Action<Unit>:
    shared_upload(device, source_memory, Array.fork(U32,A.words()))
    upload(device, source_memory, W.zero(), W.of_u32(1), 0)
    one : List<U32> <- V.Device.read_memory(device, source_memory, W.zero(), 1)
    Demo.require(Demo.bytes_equal(one, [4]), "One byte packing")
    upload(device, source_memory, W.of_u32(1), W.of_u32(3), 0)
    three : List<U32> <- V.Device.read_memory(device, source_memory, W.of_u32(1), 3)
    Demo.require(Demo.bytes_equal(three, [4,3,2]), "Three byte packing")
    upload(device, source_memory, W.of_u32(5), W.of_u32(4), 0)
    four : List<U32> <- V.Device.read_memory(device, source_memory, W.of_u32(5), 4)
    Demo.require(Demo.bytes_equal(four, [4,3,2,1]), "Four byte packing")
    upload(device, source_memory, W.of_u32(3), W.of_u32(7), 0)
    seven : List<U32> <- V.Device.read_memory(device, source_memory, W.of_u32(3), 7)
    Demo.require(Demo.bytes_equal(seven, [4,3,2,1,5,6,7]), "Seven byte packing")
    upload(device, source_memory, W.zero(), W.of_u32(17), 1610612739)
    upload(device, source_memory, W.U64{0,1}, W.of_u32(1), 1610612739)
    upload(device, source_memory, W.zero(), W.U64{0,1}, 1610612741)
    upload(device, source_memory, W.zero(), W.zero(), 0)
    upload(V.Device{4294967295}, source_memory, W.zero(), W.of_u32(1), 1610612738)
    upload(device, V.DeviceMemory{4294967295}, W.zero(), W.of_u32(1), 1610612738)
    +alias : V.Buffer <- V.Device.create_buffer(device, V.BufferCreateInfo{W.of_u32(64), 3})
    V.Device.bind_buffer_memory(device, alias, source_memory, W.zero())
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device, pool)
    V.CommandBuffer.begin(command)
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, alias, [V.BufferCopy{W.zero(),W.zero(),W.of_u32(1)}]))
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, dst, []))
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, dst, [V.BufferCopy{W.zero(),W.zero(),W.zero()}]))
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, dst, [V.BufferCopy{W.U64{0,1},W.zero(),W.of_u32(1)}]))
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, dst, [V.BufferCopy{W.zero(),W.zero(),W.of_u32(4)},V.BufferCopy{W.of_u32(8),W.of_u32(3),W.of_u32(4)}]))
    T.expect_error(Unit, 1610612739, V.CommandBuffer.copy_buffer(command, src, alias, [V.BufferCopy{W.zero(),W.of_u32(8),W.of_u32(4)},V.BufferCopy{W.of_u32(8),W.of_u32(16),W.of_u32(4)}]))
    V.CommandBuffer.copy_buffer(command, src, dst, [V.BufferCopy{W.of_u32(3),W.of_u32(5),W.of_u32(7)}])
    V.CommandBuffer.pipeline_barrier(command, 4096, 16384, [V.MemoryBarrier{4096,8192}], [])
    V.CommandBuffer.end(command)
    V.Device.submit_and_wait(device, command)
    copied : List<U32> <- V.Device.read_memory(device, dest_memory, W.of_u32(5), 7)
    Demo.require(Demo.bytes_equal(copied, [4,3,2,1,5,6,7]), "Unaligned seven-byte GPU copy")
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, src))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, dst))
    return Unit{}

def transfer_destination(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, source: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  do V.Action<Unit>:
    destination : V.Buffer & V.DeviceMemory <- buffer(instance, physical, device, 3, 2)
    transfer_body(device, source, destination)

def transfer_checks(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Unit):
  do V.Action<Unit>:
    source : V.Buffer & V.DeviceMemory <- buffer(instance, physical, device, 3, 2)
    transfer_destination(instance, physical, device, source)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance, physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families, 1), "No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance, physical, V.DeviceCreateInfo{family, []})
    transfer_checks(instance, physical, device)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit, entry => run(entry))
    V.or_exit(Unit, result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32, live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0), "Transfer cleanup leaked")
    V.or_exit(Unit, checked)
    IO.print("Packed upload and GPU copy passed")
