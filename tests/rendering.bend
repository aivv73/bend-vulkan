import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T
import ./images.bend as Images
import ./offscreen.bend as O
import ../examples/offscreen_roundtrip.bend as Example

type Attachment is Data:
  Attachment{image: V.ImageHandle, memory: V.DeviceMemory, view: V.ImageView, host_visible: Bool}

def preferred_memory(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, preferred: Maybe<U32>, requirements: V.MemoryRequirements) -> V.Action(V.DeviceMemory & Bool):
  match preferred:
    case Some{index}:
      V.MemoryRequirements{size,alignment,bits} = requirements
      do V.Action<V.DeviceMemory & Bool>:
        memory : V.DeviceMemory <- V.Device.allocate_memory(device,size,index)
        return (memory,True{})
    case None{}:
      do V.Action<V.DeviceMemory & Bool>:
        memory : V.DeviceMemory <- Example.allocate(instance,physical,device,requirements,0)
        return (memory,False{})

def bound_attachment(+device: V.Device, +image: V.ImageHandle, aspect: U32, pair: V.DeviceMemory & Bool) -> V.Action(Attachment):
  (+memory,visible) = pair
  do V.Action<Attachment>:
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return Attachment{image,memory,view,visible}

def attachment_requirements(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +image: V.ImageHandle, aspect: U32, +requirements: V.MemoryRequirements) -> V.Action(Attachment):
  V.MemoryRequirements{size,alignment,bits} = requirements
  do V.Action<Attachment>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance,physical)
    pair : V.DeviceMemory & Bool <- preferred_memory(instance,physical,device,Core.find_memory_type(types,bits,2),requirements)
    bound_attachment(device,image,aspect,pair)

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, format: U32, aspect: U32, usage: U32) -> V.Action(Attachment):
  do V.Action<Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,V.Extent2D{8,4},1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    attachment_requirements(instance,physical,device,image,aspect,requirements)

def host_after(+device: V.Device, +memory: V.DeviceMemory, visible: Bool) -> V.Action(Unit):
  match visible:
    case True{}:
      do V.Action<Unit>:
        raw_allocation_byte : List<U32> <- V.Device.read_memory(device,memory,W.zero(),1)
        return Unit{}
    case False{}:
      T.expect_error(List<U32>,1610612739,V.Device.read_memory(device,memory,W.zero(),1))

def prepare(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, color: V.ImageHandle, depth: V.ImageHandle) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    O.transition(command,color,V.ImageSubresourceRange{1,0,1,0,1},0,2,1,1024,0,256)
    O.transition(command,depth,V.ImageSubresourceRange{2,0,1,0,1},0,3,1,768,0,1024)
    O.complete(device,command,fence)
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def framebuffer_only(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, +framebuffer: V.Framebuffer, +pass: V.RenderPass, color: Attachment, depth: Attachment, stage: O.Staging) -> V.Action(Unit):
  Attachment{+image,+memory,+color_view,visible} = color
  Attachment{+depth_image,depth_memory,+depth_view,depth_visible} = depth
  O.Staging{+buffer,+unrelated,+offset} = stage
  +area : V.RenderArea = V.RenderArea{V.Offset2D{0,0},V.Extent2D{8,4}}
  do V.Action<Unit>:
    V.Device.write_memory(device,unrelated,offset,[205])
    V.CommandBuffer.begin(command)
    T.expect_error(Unit,1610612740,V.CommandBuffer.end_render_pass(command))
    T.expect_error(Unit,1610612739,V.CommandBuffer.begin_render_pass(command,framebuffer,area,[]))
    T.expect_error(Unit,1610612739,V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{7,0},V.Extent2D{8,4}},[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{0.5}]))
    T.expect_error(Unit,1610612739,V.CommandBuffer.begin_render_pass(command,framebuffer,area,[V.UnusedClear{},V.DepthClear{0.5}]))
    T.expect_error(Unit,1610612739,V.CommandBuffer.begin_render_pass(command,framebuffer,area,[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{1.5}]))
    V.CommandBuffer.begin_render_pass(command,framebuffer,area,[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{0.5}])
    T.expect_error(Unit,1610612740,V.CommandBuffer.begin_render_pass(command,framebuffer,area,[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{0.5}]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.end(command))
    T.expect_error(Unit,1610612740,V.CommandBuffer.fill_buffer(command,buffer,W.zero(),W.of_u32(4),0))
    T.expect_error(Unit,1610612740,V.CommandBuffer.copy_buffer(command,buffer,buffer,[V.BufferCopy{W.zero(),W.of_u32(4),W.of_u32(4)}]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.pipeline_barrier(command,4096,4096,[],[],[]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.clear_color_image(command,image,7,V.ClearColor{0.0,0.0,0.0,1.0},[V.ImageSubresourceRange{1,0,1,0,1}]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.clear_depth_image(command,depth_image,7,0.5,[V.ImageSubresourceRange{2,0,1,0,1}]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.copy_buffer_to_image(command,buffer,image,7,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}]))
    T.expect_error(Unit,1610612740,V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}]))
    V.CommandBuffer.end_render_pass(command)
    T.expect_error(Unit,1610612740,V.CommandBuffer.end_render_pass(command))
    V.CommandBuffer.end(command)
    V.Device.submit(device,command,fence)
    T.expect_error(List<U32>,1610612740,V.Device.read_memory(device,memory,W.zero(),1))
    T.expect_error(Unit,1610612740,V.Device.write_memory(device,memory,W.zero(),[]))
    untouched : List<U32> <- V.Device.read_memory(device,unrelated,offset,1)
    Demo.require(Demo.bytes_equal(untouched,[205]),"Unrelated allocation blocked by framebuffer")
    T.expect_error(Unit,1610612740,V.Device.destroy_framebuffer(device,framebuffer))
    T.expect_error(Unit,1610612740,V.Device.destroy_image_view(device,color_view))
    T.expect_error(Unit,1610612740,V.Device.destroy_image_view(device,depth_view))
    T.expect_error(Unit,1610612740,V.Device.destroy_render_pass(device,pass))
    T.expect_error(Unit,1610612740,V.Device.destroy_image(device,image))
    T.expect_error(Unit,1610612740,V.Device.free_memory(device,memory))
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Demo.require(U32.is_eq(status,0),"Framebuffer-only submission failed")
    host_after(device,memory,visible)
    T.expect_error(Unit,1610612740,V.Device.destroy_framebuffer(device,framebuffer))
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def read_images(+command: V.CommandBuffer, +color: V.ImageHandle, +depth: V.ImageHandle, +buffer: V.Buffer) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.copy_image_to_buffer(command,color,6,buffer,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    V.CommandBuffer.copy_image_to_buffer(command,depth,6,buffer,[V.BufferImageCopy{W.of_u32(128),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    O.host_barrier(command)

def copy_pass_clear(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, +color: V.ImageHandle, +depth: V.ImageHandle, stage: O.Staging) -> V.Action(Unit):
  O.Staging{buffer,+memory,+offset} = stage
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    O.transition(command,color,V.ImageSubresourceRange{1,0,1,0,1},2,6,1024,4096,256,2048)
    O.transition(command,depth,V.ImageSubresourceRange{2,0,1,0,1},3,6,768,4096,1024,2048)
    read_images(command,color,depth,buffer)
    O.complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,memory,offset,128)
    depths : List<U32> <- V.Device.read_memory(device,memory,W.add(offset,W.of_u32(128)),128)
    Demo.require(Demo.bytes_equal(colors,O.pixels(32n,[0,0,255,255])),"Vulkan 1.0 render-pass blue attachment clear")
    Demo.require(Demo.bytes_equal(depths,O.pixels(32n,[0,0,0,63])),"Vulkan 1.0 render-pass D32 depth 0.5")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def partial_expected(count: Nat, +index: U32, +depth: Bool) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      +x : U32 = U32.mod(index,8)
      +y : U32 = U32.div(index,8)
      inside : Bool = Bool.and(Bool.and(U32.is_ge(x,2),U32.is_lt(x,5)),Bool.and(U32.is_ge(y,1),U32.is_lt(y,3)))
      pixel : List<&2,U32> = Bool.pick(List<&2,U32>,inside,Bool.pick(List<&2,U32>,depth,[0,0,0,63],[0,255,0,255]),Bool.pick(List<&2,U32>,depth,[0,0,128,63],[255,0,0,255]))
      List.append(&1,U32,O.copy_bytes(pixel),partial_expected(rest,U32.inc(index),depth))

def partial_clear(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, framebuffer: V.Framebuffer, +color: V.ImageHandle, +depth: V.ImageHandle, stage: O.Staging) -> V.Action(Unit):
  O.Staging{+buffer,+memory,+offset} = stage
  +color_range : V.ImageSubresourceRange = V.ImageSubresourceRange{1,0,1,0,1}
  +depth_range : V.ImageSubresourceRange = V.ImageSubresourceRange{2,0,1,0,1}
  expected_color expected_depth = partial_expected(32n,0,False{}) partial_expected(32n,0,True{})
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    O.transition(command,color,color_range,6,7,4096,4096,2048,4096)
    O.transition(command,depth,depth_range,6,7,4096,4096,2048,4096)
    V.CommandBuffer.clear_color_image(command,color,7,V.ClearColor{1.0,0.0,0.0,1.0},[color_range])
    V.CommandBuffer.clear_depth_image(command,depth,7,1.0,[depth_range])
    O.transition(command,color,color_range,7,2,4096,1024,4096,256)
    O.transition(command,depth,depth_range,7,3,4096,768,4096,1024)
    V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{2,1},V.Extent2D{3,2}},[V.ColorClear{V.ClearColor{0.0,1.0,0.0,1.0}},V.DepthClear{0.5}])
    V.CommandBuffer.end_render_pass(command)
    O.transition(command,color,color_range,2,6,1024,4096,256,2048)
    O.transition(command,depth,depth_range,3,6,768,4096,1024,2048)
    read_images(command,color,depth,buffer)
    O.complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,memory,offset,128)
    depths : List<U32> <- V.Device.read_memory(device,memory,W.add(offset,W.of_u32(128)),128)
    Demo.require(Demo.bytes_equal(colors,expected_color),"Partial render area color and outside preservation")
    Demo.require(Demo.bytes_equal(depths,expected_depth),"Partial render area depth and outside preservation")
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    return Unit{}

def render(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +color: Attachment, +depth: Attachment) -> V.Action(Unit):
  Attachment{+color_image,+color_memory,+color_view,+visible} = color
  Attachment{+depth_image,+depth_memory,+depth_view,depth_visible} = depth
  do V.Action<Unit>:
    V.Action.lift(Unit,IO.print(Bool.pick(String,visible,"Optimal color image has host-visible memory","Optimal color image has no host-visible type; staging readback used")))
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    T.expect_error(V.Framebuffer,1610612739,V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[depth_view,color_view],V.Extent2D{8,4}}))
    T.expect_error(V.Framebuffer,1610612739,V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[color_view,depth_view],V.Extent2D{9,4}}))
    T.expect_error(V.Framebuffer,1610612739,V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[color_view],V.Extent2D{8,4}}))
    +framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[color_view,depth_view],V.Extent2D{8,4}})
    +stage : O.Staging <- O.staging(instance,physical,device)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    prepare(device,command,fence,color_image,depth_image)
    framebuffer_only(device,command,fence,framebuffer,pass,color,depth,stage)
    copy_pass_clear(device,command,fence,color_image,depth_image,stage)
    partial_clear(device,command,fence,framebuffer,color_image,depth_image,stage)
    V.Device.destroy_framebuffer(device,framebuffer)
    T.expect_error(Unit,1610612738,V.Device.destroy_framebuffer(device,framebuffer))
    T.expect_error(Unit,1610612740,V.Device.destroy_image(device,color_image))
    V.Device.destroy_image_view(device,color_view)
    V.Device.destroy_image_view(device,depth_view)
    V.Device.destroy_render_pass(device,pass)
    V.Device.destroy_image(device,color_image)
    V.Device.destroy_image(device,depth_image)
    V.Device.free_memory(device,color_memory)
    V.Device.free_memory(device,depth_memory)
    return Unit{}

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    T.expect_error(V.RenderPass,1610612739,V.Device.create_render_pass(device,V.RenderPassCreateInfo{[],None{}}))
    T.expect_error(V.RenderPass,1610612739,V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{126,1,0}],None{}}))
    +color : Attachment <- attachment(instance,physical,device,37,1,19)
    depth : Attachment <- attachment(instance,physical,device,126,2,35)
    render(instance,physical,device,color,depth)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Render pass cleanup leaked")
    V.or_exit(Unit,checked)
    IO.print("Real color+D32 pass clears, partial preservation and framebuffer-only pending host exclusion passed")
