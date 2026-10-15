import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as Shaders
import ./buffer_roundtrip.bend as Demo
import ./offscreen_roundtrip.bend as Memory

type Attachment is Data:
  Attachment{image: V.ImageHandle, memory: V.DeviceMemory, view: V.ImageView}
type BoundBuffer is Data:
  BoundBuffer{buffer: V.Buffer, memory: V.DeviceMemory}
type Scene is Data:
  Scene{device: V.Device, command: V.CommandBuffer, fence: V.Fence, framebuffer: V.Framebuffer, pipeline: V.GraphicsPipeline, color: Attachment, depth: Attachment, vertices: BoundBuffer, indices16: BoundBuffer, indices32: BoundBuffer, stage: BoundBuffer}

def area() -> V.RenderArea:
  V.RenderArea{V.Offset2D{0,0},V.Extent2D{8,4}}

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +format: U32, +aspect: U32, usage: U32) -> V.Action(Attachment):
  do V.Action<Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,V.Extent2D{8,4},1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return Attachment{image,memory,view}

def buffer(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, size: U32, usage: U32) -> V.Action(BoundBuffer):
  do V.Action<BoundBuffer>:
    +buffer : V.Buffer <- V.Device.create_buffer(device,V.BufferCreateInfo{W.of_u32(size),usage})
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,buffer)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,2)
    V.Device.bind_buffer_memory(device,buffer,memory,W.zero())
    return BoundBuffer{buffer,memory}

def word_bytes(+word: U32) -> List<U32>:
  [Core.word_byte(word,0),Core.word_byte(word,1),Core.word_byte(word,2),Core.word_byte(word,3)]

def bytes(words: List<U32>) -> List<U32>:
  match words:
    case Nil{}:
      []
    case Con{word,rest}:
      head tail = word_bytes(word) bytes(rest)
      List.append(&1,U32,head,tail)

def vertex(+screen_x: F32, +screen_y: F32, z: F32, color: List<U32>) -> List<U32>:
  +y : F32 = (screen_y - 1.5 : F32)
  x : F32 = (screen_x * 0.5 - y * 0.5 - 2.5 : F32)
  F32.bits(x) <> F32.bits(y) <> F32.bits(z) <> color

def copy_words(words: List<&2,U32>) -> List<U32>:
  match words:
    case Nil{}:
      []
    case Con{word,rest}:
      word <> copy_words(rest)

def quad(+left: F32, +top: F32, +right: F32, +bottom: F32, +z_left: F32, +z_right: F32, +color: List<&2,U32>) -> List<U32>:
  a b c d = vertex(left,top,z_left,copy_words(color)) vertex(right,top,z_right,copy_words(color)) vertex(right,bottom,z_right,copy_words(color)) vertex(left,bottom,z_left,copy_words(color))
  List.concat(&1,U32,[a,b,c,d])

def mesh_words() -> List<U32>:
  List.concat(&1,U32,[[0,0,0,0],
    quad(1.0,0.0,5.0,3.0,0.75,0.75,[1065353216,0,0]),
    quad(2.0,1.0,4.0,3.0,0.25,0.25,[0,1065353216,0]),
    quad(F32.neg(2.0),F32.neg(1.0),2.0,2.0,0.5,0.5,[1065353216,1065353216,0]),
    quad(0.0,0.0,4.0,2.0,F32.neg(0.5),0.5,[1065353216,0,1065353216]),
    quad(0.0,0.0,4.0,2.0,0.5,1.5,[0,1065353216,1065353216])])

def indices(+base: U32) -> List<U32>:
  [base,U32.add(base,1),U32.add(base,2),U32.add(base,2),U32.add(base,3),base]

def index_values() -> List<U32>:
  List.concat(&1,U32,[[0],indices(3),indices(7),indices(11),indices(15),indices(19)])

def u16_bytes(values: List<U32>) -> List<U32>:
  match values:
    case Nil{}:
      []
    case Con{+value,rest}:
      Core.word_byte(value,0) <> Core.word_byte(value,1) <> u16_bytes(rest)

def camera(+shift: Bool) -> List<U32>:
  [1056964608,0,0,0,1048576000,1056964608,0,0,0,0,1065353216,0,Bool.pick(U32,shift,1056964608,1048576000),3196059648,0,1065353216]

def pipeline_info(layout: V.PipelineLayout, pass: V.RenderPass, vertex: V.ShaderModule, fragment: V.ShaderModule, front: U32) -> V.GraphicsPipelineCreateInfo:
  V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[V.VertexInputBinding{0,24,vk.VK_VERTEX_INPUT_RATE_VERTEX()}],[V.VertexInputAttribute{0,0,vk.VK_FORMAT_R32G32B32_SFLOAT(),0},V.VertexInputAttribute{1,0,vk.VK_FORMAT_R32G32B32_SFLOAT(),12}],vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST(),V.RasterState{vk.VK_CULL_MODE_BACK_BIT(),front},Some{V.DepthState{True{},True{},vk.VK_COMPARE_OP_LESS()}},15}

def transition(+command: V.CommandBuffer, image: V.ImageHandle, aspect: U32, old: U32, new: U32, src_stage: U32, dst_stage: U32, src: U32, dst: U32) -> V.Action(Unit):
  V.CommandBuffer.pipeline_barrier(command,src_stage,dst_stage,[],[],[V.ImageMemoryBarrier{image,V.ImageSubresourceRange{aspect,0,1,0,1},old,new,src,dst}])

def complete(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.end(command)
    V.Device.submit(device,command,fence)
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Demo.require(U32.is_eq(status,0),"Indexed frame fence did not complete")

def reset(+device: V.Device, +command: V.CommandBuffer, fence: V.Fence) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)

def prepare(+scene: Scene) -> V.Action(Unit):
  Scene{+device,+command,+fence,framebuffer,pipeline,Attachment{color,cm,cv},Attachment{depth,dm,dv},BoundBuffer{+vertices,vm},BoundBuffer{+i16,m16},BoundBuffer{+i32,m32},stage} = scene
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,4,[],[V.BufferMemoryBarrier{vertices,W.zero(),Core.whole_size(),16384,4},V.BufferMemoryBarrier{i16,W.zero(),Core.whole_size(),16384,2},V.BufferMemoryBarrier{i32,W.zero(),Core.whole_size(),16384,2}],[])
    transition(command,color,1,0,6,1,4096,0,2048)
    transition(command,depth,2,0,6,1,4096,0,2048)
    complete(device,command,fence)
    reset(device,command,fence)

def upload(+device: V.Device, vertices: BoundBuffer, i16: BoundBuffer, i32: BoundBuffer) -> V.Action(Unit):
  BoundBuffer{vb,vm} = vertices
  BoundBuffer{b16,m16} = i16
  BoundBuffer{b32,m32} = i32
  vertex_bytes index16_bytes index32_bytes = bytes(mesh_words()) u16_bytes(index_values()) bytes(index_values())
  do V.Action<Unit>:
    V.Device.write_memory(device,vm,W.zero(),vertex_bytes)
    V.Device.write_memory(device,m16,W.of_u32(8),index16_bytes)
    V.Device.write_memory(device,m32,W.of_u32(8),index32_bytes)

def create_framebuffer(device: V.Device, pass: V.RenderPass, color: Attachment, depth: Attachment) -> V.Action(V.Framebuffer):
  Attachment{ci,cm,cv} = color
  Attachment{di,dm,dv} = depth
  V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[cv,dv],V.Extent2D{8,4}})


def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Scene):
  do V.Action<Scene>:
    +color : Attachment <- attachment(instance,physical,device,37,1,17)
    +depth : Attachment <- attachment(instance,physical,device,126,2,33)
    +vertices : BoundBuffer <- buffer(instance,physical,device,4096,128)
    +i16 : BoundBuffer <- buffer(instance,physical,device,256,64)
    +i32 : BoundBuffer <- buffer(instance,physical,device,256,64)
    +stage : BoundBuffer <- buffer(instance,physical,device,256,2)
    upload(device,vertices,i16,i32)
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.vertex_words())
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.fragment_words())
    +layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{Some{V.PushConstantRange{1,64}}})
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    +pipeline : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,pipeline_info(layout,pass,vertex,fragment,1))
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    framebuffer : V.Framebuffer <- create_framebuffer(device,pass,color,depth)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Scene{device,command,fence,framebuffer,pipeline,color,depth,vertices,i16,i32,stage}


def draw(+command: V.CommandBuffer, first: U32) -> V.Action(Unit):
  V.CommandBuffer.draw_indexed(command,V.IndexedDraw{6,1,first,V.BaseVertex{4294967293},0})

def begin_frame(+scene: Scene, +u32_indices: Bool, shift: Bool) -> V.Action(Unit):
  Scene{device,+command,fence,framebuffer,pipeline,Attachment{color,cm,cv},Attachment{depth,dm,dv},BoundBuffer{vertices,vm},BoundBuffer{i16,m16},BoundBuffer{i32,m32},stage} = scene
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    transition(command,color,1,6,2,4096,1024,2048,256)
    transition(command,depth,2,6,3,4096,768,2048,1536)
    V.CommandBuffer.begin_render_pass(command,framebuffer,area(),[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,8.0,4.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,area())
    V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.of_u32(16))
    V.CommandBuffer.bind_index_buffer(command,Bool.pick(V.Buffer,u32_indices,i32,i16),W.of_u32(8),Bool.pick(U32,u32_indices,1,0))
    V.CommandBuffer.push_constants(command,camera(shift))

def finish_frame(+scene: Scene) -> V.Action(List<U32> & List<U32>):
  Scene{+device,+command,+fence,framebuffer,pipeline,Attachment{+color,cm,cv},Attachment{+depth,dm,dv},vertices,i16,i32,BoundBuffer{+stage,+memory}} = scene
  do V.Action<List<U32> & List<U32>>:
    V.CommandBuffer.end_render_pass(command)
    transition(command,color,1,2,6,1024,4096,256,2048)
    transition(command,depth,2,3,6,768,4096,1024,2048)
    V.CommandBuffer.copy_image_to_buffer(command,color,6,stage,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    V.CommandBuffer.copy_image_to_buffer(command,depth,6,stage,[V.BufferImageCopy{W.of_u32(128),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,memory,W.zero(),128)
    depths : List<U32> <- V.Device.read_memory(device,memory,W.of_u32(128),128)
    reset(device,command,fence)
    return (colors,depths)

def expected(count: Nat, +index: U32, +shift: U32, +depth: Bool) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      +x : U32 = U32.mod(index,8)
      +y : U32 = U32.div(index,8)
      +far : Bool = Bool.and(Bool.and(U32.is_ge(x,U32.add(1,shift)),U32.is_lt(x,U32.add(5,shift))),U32.is_lt(y,3))
      +near : Bool = Bool.and(Bool.and(U32.is_ge(x,U32.add(2,shift)),U32.is_lt(x,U32.add(4,shift))),Bool.and(U32.is_ge(y,1),U32.is_lt(y,3)))
      pixel : List<U32> = Bool.pick(List<U32>,depth,Bool.pick(List<U32>,near,[0,0,128,62],Bool.pick(List<U32>,far,[0,0,64,63],[0,0,128,63])),Bool.pick(List<U32>,near,[0,255,0,255],Bool.pick(List<U32>,far,[255,0,0,255],[0,0,255,255])))
      List.append(&1,U32,pixel,expected(rest,U32.inc(index),shift,depth))

def check(pair: List<U32> & List<U32>, colors: List<U32>, depths: List<U32>) -> V.Action(Unit):
  (actual_color,actual_depth) = pair
  color_ok depth_ok = Demo.bytes_equal(actual_color,colors) Demo.bytes_equal(actual_depth,depths)
  do V.Action<Unit>:
    Demo.require(color_ok,"Indexed RGBA8 pixel mismatch")
    Demo.require(depth_ok,"Indexed D32 pixel mismatch")

def frame(+scene: Scene, u32_indices: Bool, +reverse: Bool, +shift: Bool) -> V.Action(Unit):
  Scene{device,+command,fence,framebuffer,pipeline,color,depth,vertices,i16,i32,stage} = scene
  expected_color expected_depth = expected(32n,0,Bool.pick(U32,shift,1,0),False{}) expected(32n,0,Bool.pick(U32,shift,1,0),True{})
  do V.Action<Unit>:
    begin_frame(scene,u32_indices,shift)
    draw(command,Bool.pick(U32,reverse,7,1))
    draw(command,Bool.pick(U32,reverse,1,7))
    pair : List<U32> & List<U32> <- finish_frame(scene)
    check(pair,expected_color,expected_depth)


def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +scene : Scene <- create(instance,physical,device)
    prepare(scene)
    frame(scene,False{},False{},False{})
    frame(scene,False{},True{},False{})
    frame(scene,True{},False{},False{})
    frame(scene,True{},True{},False{})
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Indexed example leaked")
    V.or_exit(Unit,checked)
    IO.print("Indexed RGBA8+D32 every-pixel occlusion in both orders, U16/U32 offsets and negative base vertex passed")
