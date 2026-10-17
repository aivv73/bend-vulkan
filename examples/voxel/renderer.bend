import Base
import ../../Vulkan.bend as V
import ../../src/core.bend as Core
import ../../deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-voxel/render.bend as R
import ../../shaders/spirv.bend as S
import ../indexed_offscreen.bend as E
import ../buffer_roundtrip.bend as D
import ../offscreen_roundtrip.bend as Memory
import ./mesh.bend as M

type Geometry is Data:
  Empty{}
  Geometry{vertices: E.BoundBuffer, indices: E.BoundBuffer, count: U32}
type Renderer is Data:
  Renderer{instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, command: V.CommandBuffer, fence: V.Fence, framebuffer: V.Framebuffer, color: E.Attachment, depth: E.Attachment, stage: E.BoundBuffer, basic: V.GraphicsPipeline, material: V.GraphicsPipeline, direction: V.GraphicsPipeline, geometry: Geometry, uploads: U32}

def area() -> V.RenderArea:
  V.RenderArea{V.Offset2D{0,0},V.Extent2D{512,512}}

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +format: U32, +aspect: U32, usage: U32) -> V.Action(E.Attachment):
  do V.Action<E.Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,V.Extent2D{512,512},1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return E.Attachment{image,memory,view}

def pipeline_finished(+device: V.Device, fragment: V.ShaderModule, result: V.VkResult(V.GraphicsPipeline)) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    V.Device.destroy_shader_module(device,fragment)
    IO.pure(V.VkResult(V.GraphicsPipeline),result)

def pipeline(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, vertex: V.ShaderModule, words: List<U32>) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,words)
    result : V.VkResult(V.GraphicsPipeline) <- V.Action.lift(V.VkResult(V.GraphicsPipeline),V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[V.VertexInputBinding{0,20,0}],[V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,37,12},V.VertexInputAttribute{2,0,37,16}],3,V.RasterState{2,0},Some{V.DepthState{True{},True{},1}},15}))
    pipeline_finished(device,fragment,result)

def framebuffer(device: V.Device, pass: V.RenderPass, color: E.Attachment, depth: E.Attachment) -> V.Action(V.Framebuffer):
  E.Attachment{ci,cm,cv} = color
  E.Attachment{di,dm,dv} = depth
  V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[cv,dv],V.Extent2D{512,512}})

def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Renderer):
  do V.Action<Renderer>:
    +color : E.Attachment <- attachment(instance,physical,device,37,1,17)
    +depth : E.Attachment <- attachment(instance,physical,device,126,2,33)
    stage : E.BoundBuffer <- E.buffer(instance,physical,device,2097152,2)
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,S.voxel_vertex_words())
    +layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{1,64}}})
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    basic : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_fragment_words())
    material : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_material_words())
    direction : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_direction_words())
    V.Device.destroy_shader_module(device,vertex)
    fb : V.Framebuffer <- framebuffer(device,pass,color,depth)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,material,direction,Empty{},0}

def prepare(renderer: Renderer) -> V.Action(Unit):
  Renderer{instance,physical,+device,+command,+fence,fb,E.Attachment{color,cm,cv},E.Attachment{depth,dm,dv},stage,basic,mat,dir,geometry,uploads} = renderer
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    E.transition(command,color,1,0,6,1,4096,0,2048)
    E.transition(command,depth,2,0,6,1,4096,0,2048)
    E.complete(device,command,fence)
    E.reset(device,command,fence)

def release_buffer(+device: V.Device, buffer: E.BoundBuffer) -> V.Action(Unit):
  E.BoundBuffer{b,m} = buffer
  do V.Action<Unit>:
    V.Device.destroy_buffer(device,b)
    V.Device.free_memory(device,m)

def release(+device: V.Device, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Geometry{vs,ix,count}:
      do V.Action<Unit>:
        release_buffer(device,vs)
        release_buffer(device,ix)

def upload_checked(pair: Array<U32> & V.VkResult(Unit)) -> V.Action(Array<U32>):
  (words,result) = pair
  do V.Action<Array<U32>>:
    IO.pure(V.VkResult(Unit),result)
    return words

def upload(+device: V.Device, buffer: E.BoundBuffer, length: U32, words: Array<U32>) -> V.Action(Array<U32>):
  E.BoundBuffer{b,m} = buffer
  do V.Action<Array<U32>>:
    pair : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit),V.Device.write_memory_words(device,m,W.zero(),W.of_u32(length),words))
    upload_checked(pair)

def upload_mesh(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, old: Geometry, mesh: M.Mesh) -> V.Action(Geometry & M.Mesh):
  M.Mesh{fs,+count,vs,ix} = mesh
  match count:
    case 0:
      do V.Action<Geometry & M.Mesh>:
        release(device,old)
        return (Empty{},M.Mesh{fs,0,vs,ix})
    case +n:
      do V.Action<Geometry & M.Mesh>:
        release(device,old)
        +vb : E.BoundBuffer <- E.buffer(instance,physical,device,(n * 80 : U32),128)
        +ib : E.BoundBuffer <- E.buffer(instance,physical,device,(n * 24 : U32),64)
        vertices : Array<U32> <- upload(device,vb,(n * 80 : U32),vs)
        indices : Array<U32> <- upload(device,ib,(n * 24 : U32),ix)
        return (Geometry{vb,ib,(n * 6 : U32)},M.Mesh{fs,n,vertices,indices})

def mesh_replaced(renderer: Renderer, result: Geometry & M.Mesh) -> Renderer & M.Mesh:
  Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,old,uploads} = renderer
  (geometry,M.Mesh{fs,+count,vs,ix}) = result
  (Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,(uploads + Bool.pick(U32,U32.is_zero(count),0,2) : U32)},M.Mesh{fs,count,vs,ix})

def replace_mesh(+renderer: Renderer, mesh: M.Mesh) -> V.Action(Renderer & M.Mesh):
  Renderer{+instance,+physical,+device,command,fence,fb,color,depth,stage,basic,mat,dir,old,uploads} = renderer
  do V.Action<Renderer & M.Mesh>:
    result : Geometry & M.Mesh <- upload_mesh(instance,physical,device,old,mesh)
    return mesh_replaced(renderer,result)

def matrix_extent(basis: R.Basis, width: U32, height: U32) -> List<U32>:
  R.Basis{+eye,R.Vec3{+rx,+ry,+rz},R.Vec3{+ux,+uy,+uz},R.Vec3{+fx,+fy,+fz},focal,near} = basis
  +scale = (focal / 256.0 : F32)
  +horizontal = (scale * U32.to_f32(height) / U32.to_f32(width) : F32)
  +tx = F32.neg(R.Vec3.dot(eye,R.Vec3{rx,ry,rz}))
  +ty = F32.neg(R.Vec3.dot(eye,R.Vec3{ux,uy,uz}))
  +tz = F32.neg(R.Vec3.dot(eye,R.Vec3{fx,fy,fz}))
  [F32.bits((horizontal * rx : F32)),F32.bits(F32.neg((scale * ux : F32))),F32.bits(fx),F32.bits(fx),
   F32.bits((horizontal * ry : F32)),F32.bits(F32.neg((scale * uy : F32))),F32.bits(fy),F32.bits(fy),
   F32.bits((horizontal * rz : F32)),F32.bits(F32.neg((scale * uz : F32))),F32.bits(fz),F32.bits(fz),
   F32.bits((horizontal * tx : F32)),F32.bits(F32.neg((scale * ty : F32))),F32.bits((tz - near : F32)),F32.bits(tz)]

def matrix(basis: R.Basis) -> List<U32>:
  matrix_extent(basis,512,512)

def draw(+command: V.CommandBuffer, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},count}:
      do V.Action<Unit>:
        V.CommandBuffer.bind_vertex_buffer(command,0,vb,W.zero())
        V.CommandBuffer.bind_index_buffer(command,ib,W.zero(),1)
        V.CommandBuffer.draw_indexed(command,V.IndexedDraw{count,1,0,V.BaseVertex{0},0})

def publish(+command: V.CommandBuffer, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},count}:
      V.CommandBuffer.pipeline_barrier(command,16384,4,[],[V.BufferMemoryBarrier{vb,W.zero(),Core.whole_size(),16384,4},V.BufferMemoryBarrier{ib,W.zero(),Core.whole_size(),16384,2}],[])

def frame(renderer: Renderer, camera: R.Camera, +mode: U32) -> V.Action(List<U32> & List<U32>):
  Renderer{instance,physical,+device,+command,+fence,fb,E.Attachment{+color,cm,cv},E.Attachment{+depth,dm,dv},E.BoundBuffer{+stage,+memory},basic,mat,dir,+geometry,uploads} = renderer
  do V.Action<List<U32> & List<U32>>:
    V.CommandBuffer.begin(command)
    publish(command,geometry)
    E.transition(command,color,1,6,2,4096,1024,2048,256)
    E.transition(command,depth,2,6,3,4096,768,2048,1536)
    V.CommandBuffer.begin_render_pass(command,fb,area(),[V.ColorClear{V.ClearColor{0.0,0.0,0.0,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,Bool.pick(V.GraphicsPipeline,U32.is_eq(mode,0),basic,Bool.pick(V.GraphicsPipeline,U32.is_eq(mode,1),mat,dir)))
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,512.0,512.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,area())
    V.CommandBuffer.push_constants(command,matrix(R.Camera.basis(camera)))
    draw(command,geometry)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    E.transition(command,depth,2,3,6,768,4096,1024,2048)
    V.CommandBuffer.copy_image_to_buffer(command,color,6,stage,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{512,512}}])
    V.CommandBuffer.copy_image_to_buffer(command,depth,6,stage,[V.BufferImageCopy{W.of_u32(1048576),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{512,512}}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,memory,W.zero(),1048576)
    depths : List<U32> <- V.Device.read_memory(device,memory,W.of_u32(1048576),1048576)
    E.reset(device,command,fence)
    return (colors,depths)

def upload_count(renderer: Renderer) -> U32:
  Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,uploads} = renderer
  uploads

def geometry_bytes(renderer: Renderer) -> V.Action(List<U32>):
  Renderer{instance,physical,+device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,uploads} = renderer
  match geometry:
    case Empty{}: V.Action.pure(List<U32>,Nil{})
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},+count}:
      do V.Action<List<U32>>:
        vs : List<U32> <- V.Device.read_memory(device,vm,W.zero(),(count / 6 * 80 : U32))
        ix : List<U32> <- V.Device.read_memory(device,im,W.zero(),(count * 4 : U32))
        return List.append(&1,U32,vs,ix)
