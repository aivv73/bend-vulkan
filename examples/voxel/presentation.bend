import Base
import ../../Vulkan.bend as V
import ../../src/core.bend as Core
import ../../deps/bend-collections/src/math/u64.bend as W
import ../../shaders/spirv.bend as S
import ../window.bend as WSI
import ../indexed_offscreen.bend as E
import ../offscreen_roundtrip.bend as Memory
import ../buffer_roundtrip.bend as D
import ./renderer.bend as GPU
import ./scene.bend as Scene
import ../../deps/bend-voxel/render.bend as R

type ImageTarget is Data:
  ImageTarget{image: V.ImageHandle, view: V.ImageView, framebuffer: V.Framebuffer}
type Target is Data:
  Target{swapchain: V.Swapchain, images: List<&2,ImageTarget>, depth: E.Attachment, pass: V.RenderPass, layout: V.PipelineLayout, pipeline: V.GraphicsPipeline, width: U32, height: U32, format: U32, production: Maybe<&2,Scene.Programs>}
type Choice is Data:
  Choice{count: U32, format: U32, space: U32, width: U32, height: U32, transform: U32, alpha: U32}
type Frame is Data:
  Frame{pool: V.CommandPool, command: V.CommandBuffer, acquire: V.Fence, render: V.Fence, present: V.Fence, finished: V.Semaphore}
type Phase is Data:
  Idle{}
  Acquiring{acquisition: V.Acquisition, index: U32, replace: Bool}
  Submitted{acquisition: V.Acquisition, index: U32, replace: Bool}
  Presenting{replace: Bool, lost: Bool}

def choice_extent(format: U32 & U32, extent: U32 & U32, count: U32, transform: U32, +alpha: U32) -> Choice:
  (f,s) = format
  (w,h) = extent
  Choice{count,f,s,w,h,transform,(alpha .&. (0 - alpha : U32) : U32)}

def choice(caps: V.SurfaceCapabilities, format: U32 & U32, width: U32, height: U32) -> Choice:
  V.SurfaceCapabilities{+minimum,+maximum,cw,ch,lw,lh,hw,hh,transforms,transform,alpha,usage} = caps
  choice_extent(format,Core.surface_extent(cw,ch,lw,lh,hw,hh,width,height),Core.present_image_count(minimum,maximum),transform,alpha)

type Owned is Data:
  OwnSwapchain{swapchain: V.Swapchain}
  OwnImage{image: V.ImageHandle}
  OwnMemory{memory: V.DeviceMemory}
  OwnView{view: V.ImageView}
  OwnPass{pass: V.RenderPass}
  OwnLayout{layout: V.PipelineLayout}
  OwnShader{shader: V.ShaderModule}
  OwnPipeline{pipeline: V.GraphicsPipeline}
  OwnFramebuffer{framebuffer: V.Framebuffer}

def release_owned(+device: V.Device, resource: Owned) -> V.Action(Unit):
  match resource:
    case OwnSwapchain{swapchain}: V.Device.destroy_swapchain(device,swapchain)
    case OwnImage{image}: V.Device.destroy_image(device,image)
    case OwnMemory{memory}: V.Device.free_memory(device,memory)
    case OwnView{view}: V.Device.destroy_image_view(device,view)
    case OwnPass{pass}: V.Device.destroy_render_pass(device,pass)
    case OwnLayout{layout}: V.Device.destroy_pipeline_layout(device,layout)
    case OwnShader{shader}: V.Device.destroy_shader_module(device,shader)
    case OwnPipeline{pipeline}: V.Device.destroy_graphics_pipeline(device,pipeline)
    case OwnFramebuffer{framebuffer}: V.Device.destroy_framebuffer(device,framebuffer)

def rollback(+device: V.Device, owned: List<&2,Owned>) -> V.Action(Unit):
  match owned:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{resource,rest}:
      do V.Action<Unit>:
        release_owned(device,resource)
        rollback(device,rest)

def guard_result(-A: Type, device: V.Device, owned: List<&2,Owned>, result: V.VkResult(A), next: A -> V.Action(Target)) -> V.Action(Target):
  match result:
    case Done{value}: next(value)
    case Fail{error}:
      do V.Action<Target>:
        rollback(device,owned)
        IO.pure(V.VkResult(Target),Fail{error})

def guard(-A: Type, +device: V.Device, owned: List<&2,Owned>, action: V.Action(A), next: A -> V.Action(Target)) -> V.Action(Target):
  IO.bind(V.VkResult(A),V.VkResult(Target),action,result => guard_result(A,device,owned,result,next))

def views(+target: Target, xs: List<V.ImageHandle>, +device: V.Device, +owned: List<&2,Owned>, +acc: List<&2,ImageTarget>) -> V.Action(Target):
  Target{swapchain,old,+depth,+pass,layout,pipeline,+width,+height,+format,+production} = target
  E.Attachment{di,dm,+dv} = depth
  match xs:
    case Nil{}: V.Action.pure(Target,Target{swapchain,acc,depth,pass,layout,pipeline,width,height,format,production})
    case Con{+image,rest}:
      guard(V.ImageView,device,owned,V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{1,0,1,0,1}}),+view =>
        guard(V.Framebuffer,device,OwnView{view} <> owned,V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view,dv],V.Extent2D{width,height}}),+framebuffer =>
          views(target,rest,device,OwnFramebuffer{framebuffer} <> OwnView{view} <> owned,ImageTarget{image,view,framebuffer} <> acc)))

def images_ready(+device: V.Device, +target: Target, +owned: List<&2,Owned>, xs: List<V.ImageHandle>) -> V.Action(Target):
  views(target,List.reverse(&1,V.ImageHandle,xs),device,owned,Nil{})

def target_pipeline(+device: V.Device, +swapchain: V.Swapchain, +depth: E.Attachment, +pass: V.RenderPass, +layout: V.PipelineLayout, +width: U32, +height: U32, +format: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.ShaderModule,device,owned,V.Device.create_shader_module(device,S.voxel_vertex_words()),+vertex =>
    guard(V.GraphicsPipeline,device,OwnShader{vertex} <> owned,GPU.pipeline(device,layout,pass,vertex,S.voxel_fragment_words()),+pipeline =>
      guard(Unit,device,OwnPipeline{pipeline} <> OwnShader{vertex} <> owned,V.Device.destroy_shader_module(device,vertex),unit =>
        guard(List<V.ImageHandle>,device,OwnPipeline{pipeline} <> owned,V.Device.swapchain_images(device,swapchain),xs =>
          images_ready(device,Target{swapchain,Nil{},depth,pass,layout,pipeline,width,height,format,None{}},OwnPipeline{pipeline} <> owned,xs)))))

def target_layout(+device: V.Device, +swapchain: V.Swapchain, +depth: E.Attachment, +pass: V.RenderPass, +width: U32, +height: U32, +format: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.PipelineLayout,device,owned,V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{1,64}}}),+layout =>
    target_pipeline(device,swapchain,depth,pass,layout,width,height,format,OwnLayout{layout} <> owned))

def target_pass(+device: V.Device, +swapchain: V.Swapchain, +depth: E.Attachment, +format: U32, +width: U32, +height: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.RenderPass,device,owned,V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{format,1,0}],Some{V.AttachmentInfo{126,1,0}}}),+pass =>
    target_layout(device,swapchain,depth,pass,width,height,format,OwnPass{pass} <> owned))

def depth_view(+device: V.Device, +swapchain: V.Swapchain, +image: V.ImageHandle, +memory: V.DeviceMemory, +format: U32, +width: U32, +height: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.ImageView,device,owned,V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{2,0,1,0,1}}),+view =>
    target_pass(device,swapchain,E.Attachment{image,memory,view},format,width,height,OwnView{view} <> owned))

def depth_memory(+context: WSI.Context, +swapchain: V.Swapchain, +image: V.ImageHandle, +format: U32, +width: U32, +height: U32, +owned: List<&2,Owned>, requirements: V.MemoryRequirements) -> V.Action(Target):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  guard(V.DeviceMemory,device,OwnImage{image} <> owned,Memory.allocate(instance,physical,device,requirements,0),+memory =>
    guard(Unit,device,OwnImage{image} <> OwnMemory{memory} <> owned,V.Device.bind_image_memory(device,image,memory,W.zero()),unit =>
      depth_view(device,swapchain,image,memory,format,width,height,OwnImage{image} <> OwnMemory{memory} <> owned)))

def target_depth(+context: WSI.Context, +swapchain: V.Swapchain, +format: U32, +width: U32, +height: U32) -> V.Action(Target):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  guard(V.ImageHandle,device,[OwnSwapchain{swapchain}],V.Device.create_image(device,V.ImageCreateInfo{126,V.Extent2D{width,height},1,1,32}),+image =>
    guard(V.MemoryRequirements,device,[OwnImage{image},OwnSwapchain{swapchain}],V.Device.get_image_memory_requirements(device,image),requirements =>
      depth_memory(context,swapchain,image,format,width,height,[OwnSwapchain{swapchain}],requirements)))

def build_chosen(+context: WSI.Context, choice: Choice) -> V.Action(Target):
  WSI.Context{window,instance,physical,+surface,+device,g,p} = context
  Choice{count,+format,space,+width,+height,transform,alpha} = choice
  guard(V.Swapchain,device,Nil{},V.Device.create_swapchain(device,V.SwapchainCreateInfo{surface,count,format,space,V.Extent2D{width,height},16,transform,alpha,2}),swapchain =>
    target_depth(context,swapchain,format,width,height))

def choose_format(format: Maybe<(U32 & U32)>) -> V.Action(U32 & U32):
  match format:
    case None{}: IO.pure(V.VkResult(U32 & U32),Fail{(1610612739,"No supported surface format")})
    case Some{pair}: V.Action.pure(U32 & U32,pair)

def build(+context: WSI.Context, +width: U32, +height: U32) -> V.Action(Target):
  WSI.Context{window,+instance,+physical,+surface,device,g,p} = context
  do V.Action<Target>:
    caps : V.SurfaceCapabilities <- V.Instance.surface_capabilities(instance,physical,surface)
    formats : List<(U32 & U32)> <- V.Instance.surface_formats(instance,physical,surface)
    format : U32 & U32 <- choose_format(Core.surface_format(formats))
    build_chosen(context,choice(caps,format,width,height))

def destroy_images(xs: List<&2,ImageTarget>, +device: V.Device) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{ImageTarget{image,view,framebuffer},rest}:
      do V.Action<Unit>:
        V.Device.destroy_framebuffer(device,framebuffer)
        V.Device.destroy_image_view(device,view)
        destroy_images(rest,device)

def destroy_production(device: V.Device, p: Maybe<&2,Scene.Programs>) -> V.Action(Unit):
  match p:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{programs}: Scene.destroy_programs(device,programs)

def destroy(+device: V.Device, target: Target) -> V.Action(Unit):
  Target{swapchain,images,E.Attachment{depth,memory,view},pass,layout,pipeline,width,height,format,production} = target
  do V.Action<Unit>:
    destroy_images(images,device)
    destroy_production(device,production)
    V.Device.destroy_graphics_pipeline(device,pipeline)
    V.Device.destroy_pipeline_layout(device,layout)
    V.Device.destroy_render_pass(device,pass)
    V.Device.destroy_image_view(device,view)
    V.Device.destroy_image(device,depth)
    V.Device.free_memory(device,memory)
    V.Device.destroy_swapchain(device,swapchain)

def frame(+device: V.Device) -> V.Action(Frame):
  do V.Action<Frame>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    acquire : V.Fence <- V.Device.create_fence(device,False{})
    render : V.Fence <- V.Device.create_fence(device,False{})
    present : V.Fence <- V.Device.create_fence(device,False{})
    finished : V.Semaphore <- V.Device.create_semaphore(device)
    return Frame{pool,command,acquire,render,present,finished}

def at(images: List<&2,ImageTarget>, index: U32) -> V.Action(ImageTarget):
  match images index:
    case Nil{} _: IO.pure(V.VkResult(ImageTarget),Fail{(1610612738,"Acquired image index out of range")})
    case Con{image,rest} 0: V.Action.pure(ImageTarget,image)
    case Con{image,rest} n: at(rest,(n - 1 : U32))

def record_image(+device: V.Device, frame: Frame, target: Target, acquisition: V.Acquisition, image: ImageTarget, camera: R.Camera, +geometry: GPU.Geometry) -> V.Action(Unit):
  Frame{pool,+command,acquire,+render,present,+finished} = frame
  Target{swapchain,images,E.Attachment{+depth,memory,dv},pass,layout,pipeline,+width,+height,+format,+production} = target
  ImageTarget{+color,view,framebuffer} = image
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.use_acquisition(command,acquisition)
    GPU.publish(command,geometry)
    E.transition(command,color,1,0,2,1024,1024,0,256)
    E.transition(command,depth,2,0,3,768,768,0,1536)
    V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}},[V.ColorClear{V.ClearColor{0.025,0.035,0.055,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,U32.to_f32(width),U32.to_f32(height),0.0,1.0})
    V.CommandBuffer.set_scissor(command,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}})
    V.CommandBuffer.push_constants(command,GPU.matrix_extent(R.Camera.basis(camera),width,height))
    GPU.draw(command,geometry)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,1000001002,1024,8192,256,0)
    V.CommandBuffer.end(command)
    V.Fence.reset(render)
    V.Device.submit_synced(device,command,render,[],[finished])

def record(+device: V.Device, +frame: Frame, +target: Target, acquisition: V.Acquisition, index: U32, camera: R.Camera, geometry: GPU.Geometry) -> V.Action(Unit):
  Target{swapchain,images,depth,pass,layout,pipeline,width,height,format,production} = target
  do V.Action<Unit>:
    image : ImageTarget <- at(images,index)
    record_image(device,frame,target,acquisition,image,camera,geometry)


def promoted(+device: V.Device, +target: Target, result: V.VkResult(Scene.Programs)) -> V.Action(Target):
  Target{sc,images,depth,pass,layout,pipeline,w,h,format,old} = target
  match result:
    case Fail{error}:
      do V.Action<Target>:
        destroy(device,target)
        IO.pure(V.VkResult(Target),Fail{error})
    case Done{programs}:
      V.Action.pure(Target,Target{sc,images,depth,pass,layout,pipeline,w,h,format,Some{programs}})

def promote(+device: V.Device, +target: Target, assets: Scene.Assets) -> V.Action(Target):
  Target{sc,images,depth,pass,layout,pipeline,w,h,format,old} = target
  do V.Action<Target>:
    result : V.VkResult(Scene.Programs) <- V.Action.lift(V.VkResult(Scene.Programs),Scene.programs(device,assets,pass))
    promoted(device,target,result)

def record_production_image(+device: V.Device, frame: Frame, target: Target, acquisition: V.Acquisition, image: ImageTarget, group: Scene.Group) -> V.Action(Unit):
  Frame{pool,+command,acquire,+render,present,+finished} = frame
  match target:
    case Target{sc,images,depth,pass,layout,pipeline,w,h,format,None{}}:
      D.require(False{},"Production target has no compatible pipelines")
    case Target{sc,images,E.Attachment{+depth,dm,dv},pass,layout,pipeline,+w,+h,format,Some{programs}}:
      ImageTarget{+color,view,framebuffer} = image
      do V.Action<Unit>:
        V.CommandBuffer.begin(command)
        V.CommandBuffer.use_acquisition(command,acquisition)
        E.transition(command,color,1,0,2,1024,1024,0,256)
        V.CommandBuffer.pipeline_barrier(command,768,768,[V.MemoryBarrier{1536,1536}],[],[])
        E.transition(command,depth,2,0,3,768,768,0,1536)
        Scene.record(command,group,programs,framebuffer,w,h,True{})
        E.transition(command,color,1,2,1000001002,1024,8192,256,0)
        V.CommandBuffer.end(command)
        V.Fence.reset(render)
        V.Device.submit_synced(device,command,render,[],[finished])

def record_production(+device: V.Device, +frame: Frame, +target: Target, acquisition: V.Acquisition, index: U32, group: Scene.Group) -> V.Action(Unit):
  Target{sc,images,depth,pass,layout,pipeline,w,h,format,production} = target
  do V.Action<Unit>:
    image : ImageTarget <- at(images,index)
    record_production_image(device,frame,target,acquisition,image,group)
