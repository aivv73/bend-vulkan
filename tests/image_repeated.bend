import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./offscreen.bend as O
import ./rendering.bend as R

def cycles(remaining: Nat, +index: U32, +device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, +framebuffer: V.Framebuffer, +color: V.ImageHandle, +depth: V.ImageHandle, +stage: O.Staging, +baseline: U32) -> V.Action(Unit):
  match remaining:
    case 0n:
      V.Action.pure(Unit,Unit{})
    case 1n+rest:
      O.Staging{+buffer,+memory,+offset} = stage
      do V.Action<Unit>:
        V.CommandBuffer.begin(command)
        O.transition(command,color,V.ImageSubresourceRange{1,0,1,0,1},0,2,1,1024,0,256)
        O.transition(command,depth,V.ImageSubresourceRange{2,0,1,0,1},0,3,1,768,0,1024)
        V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{8,4}},
          [V.ColorClear{V.ClearColor{F32.div(U32.to_f32(index),255.0),F32.div(U32.to_f32(U32.sub(255,index)),255.0),F32.div(17.0,255.0),1.0}},V.DepthClear{0.5}])
        V.CommandBuffer.end_render_pass(command)
        O.transition(command,color,V.ImageSubresourceRange{1,0,1,0,1},2,6,1024,4096,256,2048)
        O.transition(command,depth,V.ImageSubresourceRange{2,0,1,0,1},3,6,768,4096,1024,2048)
        R.read_images(command,color,depth,buffer)
        O.complete(device,command,fence)
        colors : List<U32> <- V.Device.read_memory(device,memory,offset,128)
        depths : List<U32> <- V.Device.read_memory(device,memory,W.add(offset,W.of_u32(128)),128)
        Demo.require(Demo.bytes_equal(colors,O.pixels(32n,[index,U32.sub(255,index),17,255])),"Changing attachment color cycle")
        Demo.require(Demo.bytes_equal(depths,O.pixels(32n,[0,0,0,63])),"Reused depth attachment cycle")
        V.CommandBuffer.reset(command)
        V.Fence.reset(fence)
        live : U32 <- V.debug_live_objects()
        Demo.require(U32.is_eq(live,baseline),"Image reuse grew live registry rows")
        cycles(rest,U32.inc(index),device,command,fence,framebuffer,color,depth,stage,baseline)

def destroy(+device: V.Device, framebuffer: V.Framebuffer, pass: V.RenderPass, color: R.Attachment, depth: R.Attachment) -> V.Action(Unit):
  R.Attachment{+image,+memory,view,visible} = color
  R.Attachment{+depth_image,+depth_memory,depth_view,depth_visible} = depth
  do V.Action<Unit>:
    V.Device.destroy_framebuffer(device,framebuffer)
    V.Device.destroy_image_view(device,view)
    V.Device.destroy_image_view(device,depth_view)
    V.Device.destroy_render_pass(device,pass)
    V.Device.destroy_image(device,image)
    V.Device.destroy_image(device,depth_image)
    V.Device.free_memory(device,memory)
    V.Device.free_memory(device,depth_memory)
    return Unit{}

def churn_resources(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +color: R.Attachment, +depth: R.Attachment) -> V.Action(Unit):
  R.Attachment{image,memory,+view,visible} = color
  R.Attachment{depth_image,depth_memory,+depth_view,depth_visible} = depth
  do V.Action<Unit>:
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view,depth_view],V.Extent2D{8,4}})
    destroy(device,framebuffer,pass,color,depth)

def churn(remaining: Nat, +instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +baseline: U32) -> V.Action(Unit):
  match remaining:
    case 0n:
      V.Action.pure(Unit,Unit{})
    case 1n+rest:
      do V.Action<Unit>:
        color : R.Attachment <- R.attachment(instance,physical,device,37,1,19)
        depth : R.Attachment <- R.attachment(instance,physical,device,126,2,35)
        churn_resources(instance,physical,device,color,depth)
        live : U32 <- V.debug_live_objects()
        Demo.require(U32.is_eq(live,baseline),"Image/view/pass/framebuffer churn leaked rows")
        churn(rest,instance,physical,device,baseline)

def reused(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +color: R.Attachment, +depth: R.Attachment) -> V.Action(Unit):
  R.Attachment{+image,memory,+view,visible} = color
  R.Attachment{+depth_image,depth_memory,+depth_view,depth_visible} = depth
  do V.Action<Unit>:
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    +framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view,depth_view],V.Extent2D{8,4}})
    +stage : O.Staging <- O.staging(instance,physical,device)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    baseline : U32 <- V.debug_live_objects()
    cycles(32n,1,device,command,fence,framebuffer,image,depth_image,stage,baseline)
    destroy(device,framebuffer,pass,color,depth)
    churn_baseline : U32 <- V.debug_live_objects()
    churn(32n,instance,physical,device,churn_baseline)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    color : R.Attachment <- R.attachment(instance,physical,device,37,1,19)
    depth : R.Attachment <- R.attachment(instance,physical,device,126,2,35)
    reused(instance,physical,device,color,depth)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Repeated image cleanup leaked")
    V.or_exit(Unit,checked)
    IO.print("32 distinct color+D32 pass/readback cycles and 32 image/view/pass/framebuffer churn cycles passed with bounded rows")
