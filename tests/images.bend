import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T
import ./transfers.bend as Transfer

def image(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, info: V.ImageCreateInfo, required: U32) -> V.Action(V.ImageHandle & V.DeviceMemory):
  do V.Action<V.ImageHandle & V.DeviceMemory>:
    +image : V.ImageHandle <- V.Device.create_image(device,info)
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Transfer.allocate(instance,physical,device,requirements,required)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    return (image,memory)

def resource(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +other: V.Device, +format: U32, +aspect: U32, +usage: U32) -> V.Action(Unit):
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{aspect,0,1,0,1}
  do V.Action<Unit>:
    supported : V.ImageFormatProperties <- V.Instance.get_physical_device_image_format_properties(instance,physical,V.ImageFormatInfo{format,1,0,usage,0})
    +target : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,V.Extent2D{8,4},2,2,usage})
    T.expect_error(Unit,1610612738,V.Device.destroy_image(other,target))
    T.expect_error(V.ImageView,1610612740,V.Device.create_image_view(device,V.ImageViewCreateInfo{target,1,range}))
    +requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,target)
    +memory : V.DeviceMemory <- Transfer.allocate(instance,physical,device,requirements,0)
    T.expect_error(Unit,1610612739,V.Device.bind_image_memory(device,target,memory,W.U64{0,1}))
    V.Device.bind_image_memory(device,target,memory,W.zero())
    T.expect_error(Unit,1610612740,V.Device.bind_image_memory(device,target,memory,W.zero()))
    T.expect_error(V.ImageView,1610612739,V.Device.create_image_view(device,V.ImageViewCreateInfo{target,1,V.ImageSubresourceRange{aspect,0,0,0,1}}))
    T.expect_error(V.ImageView,1610612738,V.Device.create_image_view(other,V.ImageViewCreateInfo{target,1,range}))
    +view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{target,1,range})
    +array_view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{target,5,V.ImageSubresourceRange{aspect,0,2,0,2}})
    T.expect_error(Unit,1610612740,V.Device.destroy_image(device,target))
    T.expect_error(Unit,1610612740,V.Device.free_memory(device,memory))
    T.expect_error(Unit,1610612738,V.Device.destroy_image_view(other,view))
    V.Device.destroy_image_view(device,view)
    T.expect_error(Unit,1610612738,V.Device.destroy_image_view(device,view))
    V.Device.destroy_image_view(device,array_view)
    V.Device.destroy_image(device,target)
    T.expect_error(Unit,1610612738,V.Device.destroy_image(device,target))
    V.Device.free_memory(device,memory)
    return Unit{}

def transfer_only(+device: V.Device, pair: V.ImageHandle & V.DeviceMemory) -> V.Action(Unit):
  (+target,+memory) = pair
  do V.Action<Unit>:
    T.expect_error(V.ImageView,1610612739,V.Device.create_image_view(device,V.ImageViewCreateInfo{target,1,V.ImageSubresourceRange{1,0,1,0,1}}))
    V.Device.destroy_image(device,target)
    V.Device.free_memory(device,memory)
    return Unit{}

def resources(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +other: V.Device) -> V.Action(Unit):
  do V.Action<Unit>:
    T.expect_error(V.ImageHandle,1610612739,V.Device.create_image(device,V.ImageCreateInfo{37,V.Extent2D{0,4},1,1,3}))
    T.expect_error(V.ImageHandle,1610612739,V.Device.create_image(device,V.ImageCreateInfo{37,V.Extent2D{8,4},5,1,3}))
    T.expect_error(V.ImageHandle,1610612739,V.Device.create_image(device,V.ImageCreateInfo{1,V.Extent2D{8,4},1,1,3}))
    T.expect_error(V.ImageFormatProperties,1610612739,V.Instance.get_physical_device_image_format_properties(instance,physical,V.ImageFormatInfo{999,1,0,3,0}))
    resource(instance,physical,device,other,37,1,23)
    resource(instance,physical,device,other,43,1,23)
    resource(instance,physical,device,other,44,1,23)
    resource(instance,physical,device,other,50,1,23)
    resource(instance,physical,device,other,124,2,35)
    resource(instance,physical,device,other,126,2,35)
    pair : V.ImageHandle & V.DeviceMemory <- image(instance,physical,device,V.ImageCreateInfo{37,V.Extent2D{8,4},1,1,3},0)
    transfer_only(device,pair)
    return Unit{}

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    +family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +other : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    resources(instance,physical,device,other)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Image resource cleanup leaked")
    V.or_exit(Unit,checked)
    IO.print("Six optimal image formats, requirements, views and resource lifetimes passed")
