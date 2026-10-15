import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./images.bend as Images
import ./offscreen.bend as O

def color_check(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, stage: O.Staging, pair: V.ImageHandle & V.DeviceMemory, expected: List<&2,U32>) -> V.Action(Unit):
  O.Staging{+buffer,+readback,+offset} = stage
  (+image,+memory) = pair
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{1,0,1,0,1}
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    O.transition(command,image,range,0,7,1,4096,0,4096)
    V.CommandBuffer.clear_color_image(command,image,7,V.ClearColor{1.0,0.0,0.0,1.0},[range])
    O.transition(command,image,range,7,6,4096,4096,4096,2048)
    V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    O.host_barrier(command)
    O.complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,readback,offset,64)
    Demo.require(Demo.bytes_equal(bytes,O.pixels(16n,expected)),"Raw RGBA/BGRA and sRGB endpoint channel order")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    V.Device.write_memory(device,readback,offset,O.pixels(16n,[17,31,63,127]))
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,4096,[V.MemoryBarrier{16384,2048}],[],[])
    O.transition(command,image,range,6,7,4096,4096,2048,4096)
    V.CommandBuffer.copy_buffer_to_image(command,buffer,image,7,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{2048,4096}],[],[])
    V.CommandBuffer.fill_buffer(command,buffer,W.zero(),W.of_u32(64),3452816845)
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{4096,4096}],[],[V.ImageMemoryBarrier{image,range,7,6,4096,2048}])
    V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    O.host_barrier(command)
    O.complete(device,command,fence)
    encoded : List<U32> <- V.Device.read_memory(device,readback,offset,64)
    Demo.require(Demo.bytes_equal(encoded,O.pixels(16n,[17,31,63,127])),"Every raw channel and encoded sRGB byte survives copies")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    V.Device.destroy_image(device,image)
    V.Device.free_memory(device,memory)
    return Unit{}

def color(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, command: V.CommandBuffer, fence: V.Fence, stage: O.Staging, format: U32, expected: List<&2,U32>) -> V.Action(Unit):
  do V.Action<Unit>:
    pair : V.ImageHandle & V.DeviceMemory <- Images.image(instance,physical,device,V.ImageCreateInfo{format,V.Extent2D{4,4},1,1,3},0)
    color_check(device,command,fence,stage,pair,expected)

def depth16(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, stage: O.Staging, pair: V.ImageHandle & V.DeviceMemory) -> V.Action(Unit):
  O.Staging{+buffer,+readback,+offset} = stage
  (+image,+memory) = pair
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{2,0,1,0,1}
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    O.transition(command,image,range,0,7,1,4096,0,4096)
    V.CommandBuffer.clear_depth_image(command,image,7,1.0,[range])
    O.transition(command,image,range,7,6,4096,4096,4096,2048)
    V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    O.host_barrier(command)
    O.complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,readback,offset,32)
    Demo.require(Demo.bytes_equal(bytes,O.pixels(16n,[255,255])),"D16 depth 1.0 exact ff ff bytes")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    V.Device.write_memory(device,readback,offset,O.pixels(16n,[0,0]))
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,4096,[V.MemoryBarrier{16384,2048}],[],[])
    O.transition(command,image,range,6,7,4096,4096,2048,4096)
    V.CommandBuffer.copy_buffer_to_image(command,buffer,image,7,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{2048,4096}],[],[])
    V.CommandBuffer.fill_buffer(command,buffer,W.zero(),W.of_u32(32),3452816845)
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{4096,4096}],[],[V.ImageMemoryBarrier{image,range,7,6,4096,2048}])
    V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    O.host_barrier(command)
    O.complete(device,command,fence)
    uploaded : List<U32> <- V.Device.read_memory(device,readback,offset,32)
    Demo.require(Demo.bytes_equal(uploaded,O.pixels(16n,[0,0])),"Every D16 depth 0.0 upload/readback byte")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    V.Device.destroy_image(device,image)
    V.Device.free_memory(device,memory)
    return Unit{}

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +stage : O.Staging <- O.staging(instance,physical,device)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    color(instance,physical,device,command,fence,stage,37,[255,0,0,255])
    color(instance,physical,device,command,fence,stage,43,[255,0,0,255])
    color(instance,physical,device,command,fence,stage,44,[0,0,255,255])
    color(instance,physical,device,command,fence,stage,50,[0,0,255,255])
    depth : V.ImageHandle & V.DeviceMemory <- Images.image(instance,physical,device,V.ImageCreateInfo{124,V.Extent2D{4,4},1,1,3},0)
    depth16(device,command,fence,stage,depth)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Format readback cleanup leaked")
    V.or_exit(Unit,checked)
    IO.print("RGBA/BGRA UNORM/SRGB raw channels and encoded bytes 17 31 63 127 passed; D16 depth 1.0 = ff ff and depth 0.0 upload = 00 00 passed")
