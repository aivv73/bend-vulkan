import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T
import ./images.bend as Images

type Staging is Data:
  Staging{buffer: V.Buffer, memory: V.DeviceMemory, offset: W.U64}

def staging_bound(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +buffer: V.Buffer, requirements: V.MemoryRequirements) -> V.Action(Staging):
  V.MemoryRequirements{+size,+alignment,bits} = requirements
  do V.Action<Staging>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance,physical)
    index : U32 <- Demo.choose(Core.find_memory_type(types,bits,2),"No host-visible staging allocation")
    +memory : V.DeviceMemory <- V.Device.allocate_memory(device,W.add(size,alignment),index)
    V.Device.bind_buffer_memory(device,buffer,memory,alignment)
    return Staging{buffer,memory,alignment}

def staging(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Staging):
  do V.Action<Staging>:
    +buffer : V.Buffer <- V.Device.create_buffer(device,V.BufferCreateInfo{W.of_u32(2048),3})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,buffer)
    staging_bound(instance,physical,device,buffer,requirements)

def complete(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.end(command)
    V.Device.submit(device,command,fence)
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Demo.require(U32.is_eq(status,0),"Offscreen fence did not complete")

def copy_bytes(bytes: List<&2,U32>) -> List<U32>:
  match bytes:
    case Nil{}:
      []
    case Con{byte,rest}:
      byte <> copy_bytes(rest)

def repeated(count: Nat, +byte: U32) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      byte <> repeated(rest,byte)

def pixels(count: Nat, +pixel: List<&2,U32>) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      List.append(&1,U32,copy_bytes(pixel),pixels(rest,pixel))

def host_barrier(command: V.CommandBuffer) -> V.Action(Unit):
  V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])

def transition(command: V.CommandBuffer, image: V.ImageHandle, range: V.ImageSubresourceRange, old: U32, new: U32, src_stage: U32, dst_stage: U32, src: U32, dst: U32) -> V.Action(Unit):
  V.CommandBuffer.pipeline_barrier(command,src_stage,dst_stage,[],[],[V.ImageMemoryBarrier{image,range,old,new,src,dst}])

def clear_readback(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, +target: V.ImageHandle, staging: Staging) -> V.Action(Unit):
  Staging{+buffer,+memory,+offset} = staging
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{1,0,2,0,2}
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    transition(command,target,range,0,7,1,4096,0,4096)
    T.expect_error(Unit,1610612739,V.CommandBuffer.clear_color_image(command,target,7,V.ClearColor{1.0,0.0,1.0,1.0},[]))
    V.CommandBuffer.clear_color_image(command,target,7,V.ClearColor{1.0,0.0,1.0,1.0},[range])
    transition(command,target,range,7,6,4096,4096,4096,2048)
    V.CommandBuffer.copy_image_to_buffer(command,target,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,1,0,2},V.Offset2D{0,0},V.Extent2D{5,3}}])
    host_barrier(command)
    complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,memory,offset,120)
    Demo.require(Demo.bytes_equal(bytes,pixels(30n,[255,0,255,255])),"Every-pixel F32 magenta clear")
    T.expect_error(Unit,1610612740,V.Device.destroy_image(device,target))
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def padded_expected() -> List<U32>:
  List.concat(&1,U32,[repeated(20n,205),
    [11,12,13,255,21,22,23,255,31,32,33,255],repeated(24n,205),
    [41,42,43,255,51,52,53,255,61,62,63,255],repeated(168n,205),
    [71,72,73,255,81,82,83,255,91,92,93,255],repeated(24n,205),
    [101,102,103,255,111,112,113,255,121,122,123,255]])

def full_expected() -> List<U32>:
  [0,0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,
   0,0,0,255,11,12,13,255,21,22,23,255,31,32,33,255,0,0,0,255,
   0,0,0,255,41,42,43,255,51,52,53,255,61,62,63,255,0,0,0,255,
   0,0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,
   0,0,0,255,71,72,73,255,81,82,83,255,91,92,93,255,0,0,0,255,
   0,0,0,255,101,102,103,255,111,112,113,255,121,122,123,255,0,0,0,255]

def padded_roundtrip(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, +target: V.ImageHandle, source: Staging, destination: Staging) -> V.Action(Unit):
  Staging{+src,+source_memory,+source_offset} = source
  Staging{+dst,+dest_memory,+dest_offset} = destination
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{1,0,2,0,2}
  +patch : V.BufferImageCopy = V.BufferImageCopy{W.of_u32(12),7,5,V.ImageSubresourceLayers{1,1,0,2},V.Offset2D{1,1},V.Extent2D{3,2}}
  upload_bytes output_bytes = repeated(2048n,171) repeated(2048n,205)
  do V.Action<Unit>:
    V.Device.write_memory(device,source_memory,source_offset,upload_bytes)
    V.Device.write_memory(device,dest_memory,dest_offset,output_bytes)
    V.Device.write_memory(device,source_memory,W.add(source_offset,W.of_u32(12)),[11,12,13,255,21,22,23,255,31,32,33,255])
    V.Device.write_memory(device,source_memory,W.add(source_offset,W.of_u32(40)),[41,42,43,255,51,52,53,255,61,62,63,255])
    V.Device.write_memory(device,source_memory,W.add(source_offset,W.of_u32(152)),[71,72,73,255,81,82,83,255,91,92,93,255])
    V.Device.write_memory(device,source_memory,W.add(source_offset,W.of_u32(180)),[101,102,103,255,111,112,113,255,121,122,123,255])
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,4096,[V.MemoryBarrier{16384,6144}],[],[])
    transition(command,target,range,6,7,4096,4096,2048,4096)
    V.CommandBuffer.clear_color_image(command,target,7,V.ClearColor{0.0,0.0,0.0,1.0},[range])
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{4096,4096}],[],[])
    T.expect_error(Unit,1610612739,V.CommandBuffer.copy_buffer_to_image(command,src,target,7,[patch,patch]))
    T.expect_error(Unit,1610612739,V.CommandBuffer.copy_buffer_to_image(command,src,target,7,[V.BufferImageCopy{Core.whole_size(),7,5,V.ImageSubresourceLayers{1,1,0,2},V.Offset2D{1,1},V.Extent2D{3,2}}]))
    V.CommandBuffer.copy_buffer_to_image(command,src,target,7,[patch])
    transition(command,target,range,7,6,4096,4096,4096,2048)
    V.CommandBuffer.copy_image_to_buffer(command,target,6,dst,[V.BufferImageCopy{W.of_u32(20),9,6,V.ImageSubresourceLayers{1,1,0,2},V.Offset2D{1,1},V.Extent2D{3,2}},
      V.BufferImageCopy{W.of_u32(512),0,0,V.ImageSubresourceLayers{1,1,0,2},V.Offset2D{0,0},V.Extent2D{5,3}},
      V.BufferImageCopy{W.of_u32(1024),0,0,V.ImageSubresourceLayers{1,0,0,2},V.Offset2D{0,0},V.Extent2D{10,6}}])
    host_barrier(command)
    complete(device,command,fence)
    padded : List<U32> <- V.Device.read_memory(device,dest_memory,dest_offset,284)
    Demo.require(Demo.bytes_equal(padded,padded_expected()),"Padded nonzero-offset two-layer payload and sentinels")
    full : List<U32> <- V.Device.read_memory(device,dest_memory,W.add(dest_offset,W.of_u32(512)),120)
    Demo.require(Demo.bytes_equal(full,full_expected()),"Nonzero mip addressing, orientation and untouched texels")
    base : List<U32> <- V.Device.read_memory(device,dest_memory,W.add(dest_offset,W.of_u32(1024)),480)
    Demo.require(Demo.bytes_equal(base,pixels(120n,[0,0,0,255])),"Upload changed untouched base mip")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def transfer(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, pair: V.ImageHandle & V.DeviceMemory) -> V.Action(Unit):
  (+target,+memory) = pair
  do V.Action<Unit>:
    +source : Staging <- staging(instance,physical,device)
    +destination : Staging <- staging(instance,physical,device)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    clear_readback(device,command,fence,target,destination)
    padded_roundtrip(device,command,fence,target,source,destination)
    V.Device.destroy_image(device,target)
    V.Device.free_memory(device,memory)
    return Unit{}

def depth_staged(+device: V.Device, +target: V.ImageHandle, stage: Staging) -> V.Action(Unit):
  Staging{+buffer,+memory,+offset} = stage
  +range : V.ImageSubresourceRange = V.ImageSubresourceRange{2,0,1,0,1}
  do V.Action<Unit>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    V.CommandBuffer.begin(command)
    transition(command,target,range,0,7,1,4096,0,4096)
    T.expect_error(Unit,1610612739,V.CommandBuffer.clear_depth_image(command,target,7,1.5,[range]))
    V.CommandBuffer.clear_depth_image(command,target,7,0.5,[range])
    transition(command,target,range,7,6,4096,4096,4096,2048)
    V.CommandBuffer.copy_image_to_buffer(command,target,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    host_barrier(command)
    complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,memory,offset,128)
    Demo.require(Demo.bytes_equal(bytes,pixels(32n,[0,0,0,63])),"D32 depth 0.5 exact bytes")
    V.CommandBuffer.reset(command)
    return Unit{}

def depth_readback(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, pair: V.ImageHandle & V.DeviceMemory) -> V.Action(Unit):
  (+target,+memory) = pair
  do V.Action<Unit>:
    +stage : Staging <- staging(instance,physical,device)
    depth_staged(device,target,stage)
    V.Device.destroy_image(device,target)
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
    pair : V.ImageHandle & V.DeviceMemory <- Images.image(instance,physical,device,V.ImageCreateInfo{37,V.Extent2D{10,6},2,2,3},0)
    transfer(instance,physical,device,pair)
    depth : V.ImageHandle & V.DeviceMemory <- Images.image(instance,physical,device,V.ImageCreateInfo{126,V.Extent2D{8,4},1,1,35},0)
    depth_readback(instance,physical,device,depth)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Offscreen transfer cleanup leaked")
    V.or_exit(Unit,checked)
    IO.print("Every-pixel clear and padded two-layer nonzero-mip offscreen transfers passed; D32 depth 0.5 = 00 00 00 3f")
