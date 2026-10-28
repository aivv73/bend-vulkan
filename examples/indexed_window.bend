import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as Shaders
import ./window.bend as Host
import ./window_scene.bend as Scene
import ./indexed_offscreen.bend as Mesh
import ./offscreen_roundtrip.bend as Memory
import ./buffer_roundtrip.bend as Check

type Renderer is Data:
  Renderer{context: Host.Context, vertices: Mesh.BoundBuffer, indices: Mesh.BoundBuffer, pool: V.CommandPool, command: V.CommandBuffer, acquire: V.Fence, render: V.Fence, present: V.Fence, finished: V.Semaphore}
type Frame is Data:
  Frame{image: V.ImageHandle, view: V.ImageView, framebuffer: V.Framebuffer}
type Target is Data:
  Target{swapchain: V.Swapchain, width: U32, height: U32, requested_width: U32, requested_height: U32, depth: Mesh.Attachment, pass: V.RenderPass, layout: V.PipelineLayout, pipeline: V.GraphicsPipeline, frames: List<&2,Frame>}

def upload(+device: V.Device, vertices: Mesh.BoundBuffer, indices: Mesh.BoundBuffer) -> V.Action(Unit):
  Mesh.BoundBuffer{vb,vm} = vertices
  Mesh.BoundBuffer{ib,im} = indices
  vertex_bytes index_bytes = Mesh.bytes(Scene.vertices()) Mesh.bytes(Scene.indices())
  do V.Action<Unit>:
    V.Device.write_memory(device,vm,W.zero(),vertex_bytes)
    V.Device.write_memory(device,im,W.zero(),index_bytes)

def create(+context: Host.Context) -> V.Action(Renderer):
  Host.Context{window,instance,physical,+surface,+device,g,p} = context
  do V.Action<Renderer>:
    +vertices : Mesh.BoundBuffer <- Mesh.buffer(instance,physical,device,672,vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT())
    +indices : Mesh.BoundBuffer <- Mesh.buffer(instance,physical,device,168,vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT())
    upload(device,vertices,indices)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    acquire : V.Fence <- V.Device.create_fence(device,False{})
    render : V.Fence <- V.Device.create_fence(device,False{})
    present : V.Fence <- V.Device.create_fence(device,False{})
    finished : V.Semaphore <- V.Device.create_semaphore(device)
    return Renderer{context,vertices,indices,pool,command,acquire,render,present,finished}

def format(value: Maybe<(U32 & U32)>) -> V.Action(U32 & U32):
  match value:
    case Some{pair}: V.Action.pure(U32 & U32,pair)
    case None{}: IO.pure(V.VkResult(U32 & U32),Fail{(1610612739,"No supported surface format")})

def depth(+context: Host.Context, +extent: V.Extent2D) -> V.Action(Mesh.Attachment):
  Host.Context{window,+instance,+physical,surface,+device,g,p} = context
  do V.Action<Mesh.Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{vk.VK_FORMAT_D32_SFLOAT(),extent,1,1,vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT()})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{vk.VK_IMAGE_ASPECT_DEPTH_BIT(),0,1,0,1}})
    return Mesh.Attachment{image,memory,view}

def frames(images: List<V.ImageHandle>, +device: V.Device, +pass: V.RenderPass, +depth_view: V.ImageView, +extent: V.Extent2D) -> V.Action(List<&2,Frame>):
  match images:
    case Nil{}: V.Action.pure(List<&2,Frame>,Nil{})
    case Con{+image,rest}:
      do V.Action<List<&2,Frame>>:
        +view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{vk.VK_IMAGE_ASPECT_COLOR_BIT(),0,1,0,1}})
        framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view,depth_view],extent})
        next : List<&2,Frame> <- frames(rest,device,pass,depth_view,extent)
        return Frame{image,view,framebuffer} <> next

def target_frames(images: List<V.ImageHandle>, device: V.Device, pass: V.RenderPass, attachment: Mesh.Attachment, extent: V.Extent2D) -> V.Action(List<&2,Frame>):
  Mesh.Attachment{image,memory,view} = attachment
  frames(images,device,pass,view,extent)

def build_extent(+context: Host.Context, +width: U32, +height: U32, +color_format: U32, space: U32, count: U32, transform: U32, alpha: U32, size: U32 & U32) -> V.Action(Target):
  Host.Context{window,instance,physical,surface,+device,g,p} = context
  (+w,+h) = size
  +extent : V.Extent2D = V.Extent2D{w,h}
  do V.Action<Target>:
    +swapchain : V.Swapchain <- V.Device.create_swapchain(device,V.SwapchainCreateInfo{surface,count,color_format,space,extent,vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT(),transform,alpha,vk.VK_PRESENT_MODE_FIFO_KHR()})
    +attachment : Mesh.Attachment <- depth(context,extent)
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{color_format,vk.VK_ATTACHMENT_LOAD_OP_CLEAR(),vk.VK_ATTACHMENT_STORE_OP_STORE()}],Some{V.AttachmentInfo{vk.VK_FORMAT_D32_SFLOAT(),vk.VK_ATTACHMENT_LOAD_OP_CLEAR(),vk.VK_ATTACHMENT_STORE_OP_STORE()}}})
    +layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{1,64}}})
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.vertex_words())
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.fragment_words())
    pipeline : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,Mesh.pipeline_info(layout,pass,vertex,fragment,vk.VK_FRONT_FACE_COUNTER_CLOCKWISE()))
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    images : List<V.ImageHandle> <- V.Device.swapchain_images(device,swapchain)
    views : List<&2,Frame> <- target_frames(images,device,pass,attachment,extent)
    return Target{swapchain,w,h,width,height,attachment,pass,layout,pipeline,views}

def build_target(+context: Host.Context, +width: U32, +height: U32, caps: V.SurfaceCapabilities, pair: U32 & U32) -> V.Action(Target):
  V.SurfaceCapabilities{minimum,maximum,cw,ch,lw,lh,hw,hh,transforms,transform,+alpha,usage} = caps
  (color_format,space) = pair
  build_extent(context,width,height,color_format,space,Core.present_image_count(minimum,maximum),transform,U32.and(alpha,U32.sub(0,alpha)),Core.surface_extent(cw,ch,lw,lh,hw,hh,width,height))

def target(+context: Host.Context, +width: U32, +height: U32) -> V.Action(Target):
  Host.Context{window,+instance,+physical,+surface,+device,g,p} = context
  do V.Action<Target>:
    caps : V.SurfaceCapabilities <- V.Instance.surface_capabilities(instance,physical,surface)
    formats : List<(U32 & U32)> <- V.Instance.surface_formats(instance,physical,surface)
    pair : U32 & U32 <- format(Core.surface_format(formats))
    build_target(context,width,height,caps,pair)

def destroy_frames(xs: List<&2,Frame>, +device: V.Device) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{Frame{image,view,framebuffer},rest}:
      do V.Action<Unit>:
        V.Device.destroy_framebuffer(device,framebuffer)
        V.Device.destroy_image_view(device,view)
        destroy_frames(rest,device)

def destroy(value: Maybe<Target>, +device: V.Device) -> V.Action(Unit):
  match value:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{Target{swapchain,w,h,rw,rh,Mesh.Attachment{image,memory,view},pass,layout,pipeline,frames}}:
      do V.Action<Unit>:
        destroy_frames(frames,device)
        V.Device.destroy_graphics_pipeline(device,pipeline)
        V.Device.destroy_pipeline_layout(device,layout)
        V.Device.destroy_render_pass(device,pass)
        V.Device.destroy_image_view(device,view)
        V.Device.destroy_image(device,image)
        V.Device.free_memory(device,memory)
        V.Device.destroy_swapchain(device,swapchain)

def wait(+fence: V.Fence) -> V.Action(Unit):
  do V.Action<Unit>:
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Check.require(U32.is_zero(status),"Window fence did not complete")
    V.Fence.reset(fence)

def frame_at(xs: List<&2,Frame>, index: U32) -> V.Action(Frame):
  match xs index:
    case Nil{} _: IO.pure(V.VkResult(Frame),Fail{(1610612739,"Swapchain image index out of range")})
    case Con{frame,rest} 0: V.Action.pure(Frame,frame)
    case Con{frame,rest} _: frame_at(rest,U32.sub(index,1))

# One frame in flight. Observe both render and presentation fences before reuse.

def record(renderer: Renderer, target: Target, frame: Frame, +lease: V.Acquisition, camera: Scene.Camera) -> V.Action(Unit):
  Renderer{Host.Context{window,instance,physical,surface,+device,g,p},Mesh.BoundBuffer{+vertices,vm},Mesh.BoundBuffer{+indices,im},pool,+command,acquire,+render,+present,+finished} = renderer
  Target{swapchain,+w,+h,rw,rh,Mesh.Attachment{depth,dm,dv},pass,layout,pipeline,frames} = target
  Frame{+image,view,framebuffer} = frame
  +depth_stages : U32 = U32.or(vk.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT(),vk.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT())
  +area : V.RenderArea = V.RenderArea{V.Offset2D{0,0},V.Extent2D{w,h}}
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.use_acquisition(command,lease)
    V.CommandBuffer.pipeline_barrier(command,vk.VK_PIPELINE_STAGE_HOST_BIT(),vk.VK_PIPELINE_STAGE_VERTEX_INPUT_BIT(),[],[V.BufferMemoryBarrier{vertices,W.zero(),Core.whole_size(),vk.VK_ACCESS_HOST_WRITE_BIT(),vk.VK_ACCESS_VERTEX_ATTRIBUTE_READ_BIT()},V.BufferMemoryBarrier{indices,W.zero(),Core.whole_size(),vk.VK_ACCESS_HOST_WRITE_BIT(),vk.VK_ACCESS_INDEX_READ_BIT()}],[])
    Mesh.transition(command,image,vk.VK_IMAGE_ASPECT_COLOR_BIT(),vk.VK_IMAGE_LAYOUT_UNDEFINED(),vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL(),vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT(),vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT(),0,vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT())
    Mesh.transition(command,depth,vk.VK_IMAGE_ASPECT_DEPTH_BIT(),vk.VK_IMAGE_LAYOUT_UNDEFINED(),vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL(),depth_stages,depth_stages,0,U32.or(vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT(),vk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT()))
    V.CommandBuffer.begin_render_pass(command,framebuffer,area,[V.ColorClear{V.ClearColor{0.055,0.075,0.12,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,U32.to_f32(w),U32.to_f32(h),0.0,1.0})
    V.CommandBuffer.set_scissor(command,area)
    V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.zero())
    V.CommandBuffer.bind_index_buffer(command,indices,W.zero(),vk.VK_INDEX_TYPE_UINT32())
    V.CommandBuffer.push_constants(command,Scene.matrix(camera,w,h))
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{42,1,0,V.BaseVertex{0},0})
    V.CommandBuffer.end_render_pass(command)
    Mesh.transition(command,image,vk.VK_IMAGE_ASPECT_COLOR_BIT(),vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL(),vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR(),vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT(),vk.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT(),vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT(),0)
    V.CommandBuffer.end(command)
    V.Device.submit_synced(device,command,render,[],[finished])
    wait(render)
    V.CommandBuffer.reset(command)

def presented(outcome: V.PresentOutcome, suboptimal: Bool) -> V.Action(Bool):
  match outcome:
    case V.Presented{}: V.Action.pure(Bool,suboptimal)
    case V.PresentSuboptimal{}: V.Action.pure(Bool,True{})
    case V.PresentOutOfDate{}: V.Action.pure(Bool,True{})
    case V.PresentSurfaceLost{}: IO.pure(V.VkResult(Bool),Fail{(1610612739,"Presentation surface lost")})

def acquired(outcome: V.AcquireOutcome, +renderer: Renderer, +target: Target, camera: Scene.Camera) -> V.Action(Bool):
  match outcome:
    case V.AcquireOutOfDate{}: V.Action.pure(Bool,True{})
    case V.AcquireNotReady{}: V.Action.pure(Bool,False{})
    case V.AcquireTimeout{}: V.Action.pure(Bool,False{})
    case V.AcquireSurfaceLost{}: IO.pure(V.VkResult(Bool),Fail{(1610612739,"Acquisition surface lost")})
    case V.Acquired{+lease,index,suboptimal}:
      Renderer{Host.Context{window,instance,physical,surface,device,g,p},vertices,indices,pool,command,acquire,render,+present,finished} = renderer
      Target{swapchain,w,h,rw,rh,depth,pass,layout,pipeline,frames} = target
      do V.Action<Bool>:
        wait(acquire)
        frame : Frame <- frame_at(frames,index)
        record(renderer,target,frame,lease,camera)
        outcome : V.PresentOutcome <- V.Device.present(device,lease,finished,present)
        wait(present)
        presented(outcome,suboptimal)

def draw(+renderer: Renderer, +target: Target, camera: Scene.Camera) -> V.Action(Bool):
  Renderer{Host.Context{window,instance,physical,surface,device,g,p},vertices,indices,pool,command,acquire,render,present,finished} = renderer
  Target{swapchain,w,h,rw,rh,depth,pass,layout,pipeline,frames} = target
  do V.Action<Bool>:
    outcome : V.AcquireOutcome <- V.Device.acquire(device,swapchain,acquire,W.of_u32(16000000))
    acquired(outcome,renderer,target,camera)

def replace(changed: Bool, value: Target, +context: Host.Context, width: U32, height: U32) -> V.Action(Target):
  match changed:
    case False{}: V.Action.pure(Target,value)
    case True{}:
      Host.Context{window,instance,physical,surface,device,g,p} = context
      do V.Action<Target>:
        destroy(Some{value},device)
        target(context,width,height)

def ensure(current: Maybe<Target>, +context: Host.Context, +width: U32, +height: U32) -> V.Action(Target):
  match current:
    case None{}: target(context,width,height)
    case Some{+value}:
      Target{swapchain,w,h,rw,rh,depth,pass,layout,pipeline,frames} = value
      replace(U32.is_ne(rw,width) || U32.is_ne(rh,height),value,context,width,height)

def retire(rebuild: Bool, value: Target, device: V.Device) -> V.Action(Maybe<Target>):
  match rebuild:
    case False{}: V.Action.pure(Maybe<Target>,Some{value})
    case True{}:
      do V.Action<Maybe<Target>>:
        destroy(Some{value},device)
        return None{}

def update(drawable: Bool, +renderer: Renderer, current: Maybe<Target>, camera: Scene.Camera, width: U32, height: U32) -> V.Action(Maybe<Target>):
  match drawable:
    case False{}: V.Action.pure(Maybe<Target>,current)
    case True{}:
      Renderer{+context,vertices,indices,pool,command,acquire,render,present,finished} = renderer
      Host.Context{window,instance,physical,surface,device,g,p} = context
      do V.Action<Maybe<Target>>:
        +value : Target <- ensure(current,context,width,height)
        rebuild : Bool <- draw(renderer,value,camera)
        retire(rebuild,value,device)

def step(camera: Maybe<Scene.Camera>, +renderer: Renderer, current: Maybe<Target>, drawable: Bool, width: U32, height: U32) -> V.Action(Maybe<(Maybe<Target> & Scene.Camera)>):
  match camera:
    case None{}:
      Renderer{Host.Context{window,instance,physical,surface,device,g,p},vertices,indices,pool,command,acquire,render,present,finished} = renderer
      do V.Action<Maybe<(Maybe<Target> & Scene.Camera)>>:
        destroy(current,device)
        return None{}
    case Some{+value}:
      do V.Action<Maybe<(Maybe<Target> & Scene.Camera)>>:
        next : Maybe<Target> <- update(drawable,renderer,current,value,width,height)
        return Some{(next,value)}

def tick(snapshot: V.WindowSnapshot, renderer: Renderer, current: Maybe<Target>, camera: Scene.Camera) -> V.Action(Maybe<(Maybe<Target> & Scene.Camera)>):
  V.WindowSnapshot{+width,+height,mapped,focused,captured,events} = snapshot
  step(Scene.events(events,Some{camera}),renderer,current,Core.drawable(mapped,width,height),width,height)

# Finite fuel keeps the event loop within Bend's termination rules (years at 60 Hz).
def loop(fuel: Nat, state: Maybe<(Maybe<Target> & Scene.Camera)>, +renderer: Renderer) -> V.Action(Unit):
  match fuel state:
    case _ None{}: V.Action.pure(Unit,Unit{})
    case 0n Some{(current,camera)}:
      Renderer{Host.Context{window,instance,physical,surface,device,g,p},vertices,indices,pool,command,acquire,render,present,finished} = renderer
      destroy(current,device)
    case 1n+rest Some{(current,camera)}:
      Renderer{Host.Context{window,instance,physical,surface,device,g,p},vertices,indices,pool,command,acquire,render,present,finished} = renderer
      do V.Action<Unit>:
        snapshot : V.WindowSnapshot <- V.NativeWindow.poll(window,16)
        next : Maybe<(Maybe<Target> & Scene.Camera)> <- tick(snapshot,renderer,current,camera)
        loop(rest,next,renderer)

def run(entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    context : Host.Context <- Host.open(entry,"Bend Vulkan - indexed mesh",False{})
    renderer : Renderer <- create(context)
    loop(U32.to_nat(4294967295),Some{(None{},Scene.initial())},renderer)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print("A/D orbit, W/S elevation, Q/E zoom, R reset; Escape or close to quit.")
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Check.require(U32.is_zero(count),"Window example leaked objects")
    V.or_exit(Unit,checked)
    V.or_exit(Unit,result)
    IO.print("Indexed window closed; live Vulkan objects: 0")
