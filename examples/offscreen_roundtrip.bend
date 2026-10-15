import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ./buffer_roundtrip.bend as Demo

def allocate(+instance: V.Instance, +physical: V.PhysicalDevice, device: V.Device, requirements: V.MemoryRequirements, required: U32) -> V.Action(V.DeviceMemory):
  V.MemoryRequirements{size,alignment,bits} = requirements
  do V.Action<V.DeviceMemory>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance,physical)
    index : U32 <- Demo.choose(Core.find_memory_type(types,bits,required),"No compatible memory type")
    V.Device.allocate_memory(device,size,index)

def expected(count: Nat) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      255 <> 0 <> 255 <> 255 <> expected(rest)

def clear(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Unit):
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{1,0,1,0,1}
  do V.Action<Unit>:
    supported : V.ImageFormatProperties <- V.Instance.get_physical_device_image_format_properties(instance,physical,V.ImageFormatInfo{37,1,0,3,0})
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{37,V.Extent2D{4,4},1,1,3})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +image_memory : V.DeviceMemory <- allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,image_memory,W.zero())
    +buffer : V.Buffer <- V.Device.create_buffer(device,V.BufferCreateInfo{W.of_u32(64),2})
    buffer_requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,buffer)
    +readback : V.DeviceMemory <- allocate(instance,physical,device,buffer_requirements,2)
    V.Device.bind_buffer_memory(device,buffer,readback,W.zero())
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT(),vk.VK_PIPELINE_STAGE_TRANSFER_BIT(),[],[],
      [V.ImageMemoryBarrier{image,range,vk.VK_IMAGE_LAYOUT_UNDEFINED(),vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL(),0,vk.VK_ACCESS_TRANSFER_WRITE_BIT()}])
    V.CommandBuffer.clear_color_image(command,image,vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL(),V.ClearColor{1.0,0.0,1.0,1.0},[range])
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[],[],[V.ImageMemoryBarrier{image,range,7,6,4096,2048}])
    V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{4,4}}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    V.CommandBuffer.end(command)
    V.Device.submit(device,command,fence)
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Demo.require(U32.is_eq(status,0),"Image fence did not complete")
    bytes : List<U32> <- V.Device.read_memory(device,readback,W.zero(),64)
    Demo.require(Demo.bytes_equal(bytes,expected(16n)),"Every RGBA8 pixel must be magenta")
    V.CommandBuffer.reset(command)
    V.Device.destroy_fence(device,fence)
    V.Device.destroy_command_pool(device,pool)
    V.Device.destroy_image(device,image)
    V.Device.destroy_buffer(device,buffer)
    V.Device.free_memory(device,image_memory)
    V.Device.free_memory(device,readback)
    V.Device.destroy(device)
    V.Instance.destroy(instance)
    return Unit{}

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    clear(instance,physical,device)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Offscreen example leaked")
    V.or_exit(Unit,checked)
    IO.print("Optimal RGBA8 image clear and every-pixel readback verified")
