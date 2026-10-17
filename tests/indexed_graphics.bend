import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as Shaders
import ../examples/indexed_offscreen.bend as E
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T

def with_pipeline(scene: E.Scene, pipeline: V.GraphicsPipeline) -> E.Scene:
  E.Scene{device,command,fence,framebuffer,old,color,depth,vertices,i16,i32,stage,layout,pass} = scene
  E.Scene{device,command,fence,framebuffer,pipeline,color,depth,vertices,i16,i32,stage,layout,pass}

def variant(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, +front: U32, +topology: U32, +mask: U32) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.vertex_words())
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.fragment_words())
    pipeline : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[V.VertexInputBinding{0,24,0}],[V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,106,12}],topology,V.RasterState{2,front},Some{V.DepthState{True{},True{},1}},mask})
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    return pipeline

def pixel_case(mode: U32, +x: U32, +y: U32, +far: Bool, +near: Bool, +clear: List<&2,U32>, +depth: Bool) -> List<U32>:
  match mode:
    case 1:
      E.copy_words(clear)
    case 2:
      Bool.pick(List<U32>,Bool.and(U32.is_lt(x,2),U32.is_lt(y,2)),Bool.pick(List<U32>,depth,[0,0,0,63],[255,255,0,255]),E.copy_words(clear))
    case 3:
      Bool.pick(List<U32>,Bool.and(Bool.and(U32.is_ge(x,2),U32.is_lt(x,4)),U32.is_lt(y,2)),Bool.pick(List<U32>,depth,Bool.pick(List<U32>,U32.is_eq(x,2),[0,0,0,62],[0,0,192,62]),[255,0,255,255]),E.copy_words(clear))
    case 4:
      Bool.pick(List<U32>,Bool.and(U32.is_lt(x,2),U32.is_lt(y,2)),Bool.pick(List<U32>,depth,Bool.pick(List<U32>,U32.is_eq(x,0),[0,0,32,63],[0,0,96,63]),[0,255,255,255]),E.copy_words(clear))
    case 5:
      Bool.pick(List<U32>,Bool.and(Bool.and(U32.is_ge(x,2),U32.is_lt(x,4)),U32.is_eq(y,1)),Bool.pick(List<U32>,depth,[0,0,64,63],[255,0,0,255]),E.copy_words(clear))
    case 7:
      +moved_near : Bool = Bool.and(Bool.and(U32.is_ge(x,3),U32.is_lt(x,5)),Bool.and(U32.is_ge(y,1),U32.is_lt(y,3)))
      Bool.pick(List<U32>,moved_near,Bool.pick(List<U32>,depth,[0,0,128,62],[0,255,0,255]),Bool.pick(List<U32>,far,Bool.pick(List<U32>,depth,[0,0,64,63],[255,0,0,255]),E.copy_words(clear)))
    case 8:
      Bool.pick(List<U32>,near,Bool.pick(List<U32>,depth,[0,0,128,62],[0,0,0,255]),Bool.pick(List<U32>,far,Bool.pick(List<U32>,depth,[0,0,64,63],[255,0,0,255]),E.copy_words(clear)))
    case _:
      Bool.pick(List<U32>,far,Bool.pick(List<U32>,depth,[0,0,64,63],[255,0,0,255]),E.copy_words(clear))

def pixel(+x: U32, +y: U32, +mode: U32, +depth: Bool) -> List<U32>:
  +far : Bool = Bool.and(Bool.and(U32.is_ge(x,1),U32.is_lt(x,5)),U32.is_lt(y,3))
  +near : Bool = Bool.and(Bool.and(U32.is_ge(x,2),U32.is_lt(x,4)),Bool.and(U32.is_ge(y,1),U32.is_lt(y,3)))
  +clear : List<&2,U32> = Bool.pick(List<&2,U32>,depth,[0,0,128,63],[0,0,255,255])
  pixel_case(mode,x,y,far,near,clear,depth)

def expected(count: Nat, +index: U32, +mode: U32, +depth: Bool) -> List<U32>:
  match count:
    case 0n:
      []
    case 1n+rest:
      List.append(&1,U32,pixel(U32.mod(index,8),U32.div(index,8),mode,depth),expected(rest,U32.inc(index),mode,depth))

def record_case(+command: V.CommandBuffer, mode: U32) -> V.Action(Unit):
  match mode:
    case 2:
      E.draw(command,13)
    case 3:
      E.draw(command,19)
    case 4:
      E.draw(command,25)
    case 5:
      do V.Action<Unit>:
        V.CommandBuffer.set_scissor(command,V.RenderArea{V.Offset2D{2,1},V.Extent2D{2,1}})
        E.draw(command,1)
    case 6:
      do V.Action<Unit>:
        V.CommandBuffer.set_viewport(command,V.Viewport{1.0,0.0,8.0,4.0,0.0,1.0})
        E.draw(command,1)
        E.draw(command,7)
    case 7:
      do V.Action<Unit>:
        E.draw(command,1)
        V.CommandBuffer.push_constants(command,E.camera(True{}))
        E.draw(command,7)
    case 8:
      do V.Action<Unit>:
        E.draw(command,1)
        E.draw(command,7)
    case 9:
      V.CommandBuffer.draw_indexed(command,V.IndexedDraw{4,1,1,V.BaseVertex{4294967293},0})
    case _:
      E.draw(command,1)

def render_case(+scene: E.Scene, +mode: U32) -> V.Action(Unit):
  E.Scene{device,command,fence,framebuffer,pipeline,color,depth,vertices,i16,i32,stage,layout,pass} = scene
  colors depths = expected(32n,0,mode,False{}) expected(32n,0,mode,True{})
  do V.Action<Unit>:
    E.begin_frame(scene,True{},False{})
    record_case(command,mode)
    pair : List<U32> & List<U32> <- E.finish_frame(scene)
    E.check(pair,Bool.pick(List<U32>,U32.is_eq(mode,6),E.expected(32n,0,1,False{}),colors),Bool.pick(List<U32>,U32.is_eq(mode,6),E.expected(32n,0,1,True{}),depths))

def repeat_frames(count: Nat, +scene: E.Scene, +index: U32, +live: U32) -> V.Action(Unit):
  match count:
    case 0n:
      V.Action.pure(Unit,Unit{})
    case 1n+rest:
      do V.Action<Unit>:
        E.frame(scene,U32.is_zero(U32.and(index,1)),U32.is_zero(U32.and(index,2)),U32.is_zero(U32.and(index,4)))
        now : U32 <- V.debug_live_objects()
        Demo.require(U32.is_eq(now,live),"Indexed reuse changed live registry rows")
        repeat_frames(rest,scene,U32.inc(index),live)

def pass_boundary(scene: E.Scene) -> V.Action(Unit):
  E.Scene{device,+command,fence,framebuffer,pipeline,E.Attachment{color,cm,cv},E.Attachment{depth,dm,dv},vertices,i16,i32,stage,layout,pass} = scene
  do V.Action<Unit>:
    E.transition(command,color,1,2,2,1024,1024,256,256)
    E.transition(command,depth,2,3,3,768,768,1024,1536)

def readiness(+scene: E.Scene) -> V.Action(Unit):
  E.Scene{+device,+command,fence,framebuffer,+pipeline,color,depth,E.BoundBuffer{+vertices,vm},i16,i32,stage,+layout,+pass} = scene
  do V.Action<Unit>:
    +stale : V.GraphicsPipeline <- variant(device,layout,pass,1,3,15)
    V.Device.destroy_graphics_pipeline(device,stale)
    +different_pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    +incompatible : V.GraphicsPipeline <- variant(device,layout,different_pass,1,3,15)
    E.begin_frame(scene,True{},False{})
    T.expect_error(Unit,1610612738,V.CommandBuffer.bind_graphics_pipeline(command,stale))
    V.CommandBuffer.bind_graphics_pipeline(command,incompatible)
    V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.of_u32(16))
    V.CommandBuffer.push_constants(command,E.camera(False{}))
    T.expect_error(Unit,1610612740,E.draw(command,1))
    T.expect_error(Unit,1610612738,V.CommandBuffer.bind_graphics_pipeline(command,V.GraphicsPipeline{0}))
    T.expect_error(Unit,1610612739,V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.of_u32(17)))
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    T.expect_error(Unit,1610612740,E.draw(command,1))
    V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.of_u32(16))
    T.expect_error(Unit,1610612740,E.draw(command,1))
    T.expect_error(Unit,1610612739,V.CommandBuffer.push_constants(command,[1,2]))
    V.CommandBuffer.push_constants(command,E.camera(False{}))
    V.CommandBuffer.end_render_pass(command)
    pass_boundary(scene)
    V.CommandBuffer.begin_render_pass(command,framebuffer,E.area(),[V.ColorClear{V.ClearColor{0.0,0.0,1.0,1.0}},V.DepthClear{1.0}])
    E.draw(command,1)
    E.draw(command,7)
    pair : List<U32> & List<U32> <- E.finish_frame(scene)
    E.check(pair,E.expected(32n,0,0,False{}),E.expected(32n,0,0,True{}))
    V.Device.destroy_graphics_pipeline(device,incompatible)
    V.Device.destroy_render_pass(device,different_pass)

def lifetime_bound(+scene: E.Scene, extra: E.BoundBuffer) -> V.Action(Unit):
  E.Scene{+device,+command,+fence,framebuffer,+pipeline,E.Attachment{+color,cm,cv},E.Attachment{+depth,dm,dv},E.BoundBuffer{+vertices,+vm},E.BoundBuffer{+i16,+m16},E.BoundBuffer{i32,+m32},stage,+layout,+pass} = scene
  E.BoundBuffer{+overwritten,+overwritten_memory} = extra
  do V.Action<Unit>:
    +overwritten_pipeline : V.GraphicsPipeline <- variant(device,layout,pass,1,3,15)
    E.begin_frame(scene,False{},False{})
    V.CommandBuffer.bind_graphics_pipeline(command,overwritten_pipeline)
    V.CommandBuffer.bind_vertex_buffer(command,0,overwritten,W.zero())
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.of_u32(16))
    V.CommandBuffer.push_constants(command,E.camera(False{}))
    E.draw(command,1)
    E.draw(command,7)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    E.transition(command,depth,2,3,6,768,4096,1024,2048)
    V.CommandBuffer.end(command)
    V.Device.submit(device,command,fence)
    T.expect_error(List<U32>,1610612740,V.Device.read_memory(device,vm,W.zero(),1))
    T.expect_error(Unit,1610612740,V.Device.write_memory(device,m16,W.zero(),[]))
    T.expect_error(List<U32>,1610612740,V.Device.read_memory(device,overwritten_memory,W.zero(),1))
    unrelated : List<U32> <- V.Device.read_memory(device,m32,W.zero(),1)
    T.expect_error(Unit,1610612740,V.Device.destroy_graphics_pipeline(device,overwritten_pipeline))
    T.expect_error(Unit,1610612740,V.Device.destroy_buffer(device,overwritten))
    status : U32 <- V.Fence.wait(fence,Core.whole_size())
    Demo.require(U32.is_eq(status,0),"Graphics lifetime submission failed")
    accessible : List<U32> <- V.Device.read_memory(device,vm,W.zero(),1)
    T.expect_error(Unit,1610612740,V.Device.destroy_graphics_pipeline(device,overwritten_pipeline))
    T.expect_error(Unit,1610612740,V.Device.destroy_buffer(device,overwritten))
    E.reset(device,command,fence)
    V.Device.destroy_graphics_pipeline(device,overwritten_pipeline)
    V.Device.destroy_buffer(device,overwritten)
    V.Device.free_memory(device,overwritten_memory)

def lifetime(+instance: V.Instance, +physical: V.PhysicalDevice, +scene: E.Scene) -> V.Action(Unit):
  E.Scene{+device,command,fence,framebuffer,pipeline,color,depth,vertices,i16,i32,stage,layout,pass} = scene
  do V.Action<Unit>:
    extra : E.BoundBuffer <- E.buffer(instance,physical,device,64,128)
    lifetime_bound(scene,extra)

def index_visibility(+scene: E.Scene) -> V.Action(Unit):
  E.Scene{+device,+command,+fence,framebuffer,pipeline,color,depth,vertices,i16,E.BoundBuffer{index_buffer,memory},stage,layout,pass} = scene
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,4,[],[V.BufferMemoryBarrier{index_buffer,W.zero(),Core.whole_size(),16384,2}],[])
    E.complete(device,command,fence)
    E.reset(device,command,fence)

def cases(+instance: V.Instance, +physical: V.PhysicalDevice, +scene: E.Scene) -> V.Action(Unit):
  E.Scene{+device,command,fence,framebuffer,pipeline,color,depth,vertices,i16,E.BoundBuffer{i32,+m32},stage,+layout,+pass} = scene
  do V.Action<Unit>:
    E.prepare(scene)
    E.frame(scene,False{},False{},False{})
    E.frame(scene,False{},True{},False{})
    E.frame(scene,True{},False{},False{})
    E.frame(scene,True{},True{},False{})
    readiness(scene)
    lifetime(instance,physical,scene)
    +reversed : V.GraphicsPipeline <- variant(device,layout,pass,0,3,15)
    render_case(with_pipeline(scene,reversed),1)
    V.Device.destroy_graphics_pipeline(device,reversed)
    render_case(scene,2)
    render_case(scene,3)
    render_case(scene,4)
    render_case(scene,5)
    render_case(scene,6)
    render_case(scene,7)
    +masked : V.GraphicsPipeline <- variant(device,layout,pass,1,3,5)
    render_case(with_pipeline(scene,masked),8)
    V.Device.destroy_graphics_pipeline(device,masked)
    +strip : V.GraphicsPipeline <- variant(device,layout,pass,1,4,15)
    V.Device.write_memory(device,m32,W.of_u32(8),E.bytes([0,3,4,6,5]))
    index_visibility(scene)
    render_case(with_pipeline(scene,strip),9)
    V.Device.destroy_graphics_pipeline(device,strip)
    V.Device.write_memory(device,m32,W.of_u32(8),E.bytes(E.index_values()))
    index_visibility(scene)
    live : U32 <- V.debug_live_objects()
    repeat_frames(32n,scene,0,live)
    V.Action.lift(Unit,IO.print("Every RGBA8/D32 pixel passed for both index widths/orders, winding, lateral/near/far clipping, orientation, dynamic state, column-major camera, changing pushes and 32 stable reuses"))

def foreign_commands(+other: V.Device, +scene: E.Scene) -> V.Action(Unit):
  E.Scene{device,command,fence,framebuffer,+pipeline,color,depth,E.BoundBuffer{+vertices,vm},E.BoundBuffer{+indices,im},i32,stage,layout,pass} = scene
  do V.Action<Unit>:
    +pool : V.CommandPool <- V.Device.create_command_pool(other)
    +foreign : V.CommandBuffer <- V.Device.allocate_command_buffer(other,pool)
    V.CommandBuffer.begin(foreign)
    T.expect_error(Unit,1610612738,V.CommandBuffer.bind_graphics_pipeline(foreign,pipeline))
    T.expect_error(Unit,1610612738,V.CommandBuffer.bind_vertex_buffer(foreign,0,vertices,W.of_u32(16)))
    T.expect_error(Unit,1610612738,V.CommandBuffer.bind_index_buffer(foreign,indices,W.of_u32(8),0))
    V.CommandBuffer.reset(foreign)
    V.Device.destroy_command_pool(other,pool)
    V.Device.destroy(other)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    +family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +scene : E.Scene <- E.create(instance,physical,device)
    other : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    foreign_commands(other,scene)
    cases(instance,physical,scene)

def abandon(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +scene : E.Scene <- E.create(instance,physical,device)
    E.prepare(scene)
    E.begin_frame(scene,True{},False{})
    unused_shader : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.vertex_words())
    unused_layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],None{}})
    IO.pure(V.VkResult(Unit),Fail{(93,"Controlled graphics scope failure")})

def all_checks() -> V.Action(Unit):
  do V.Action<Unit>:
    V.Entry.with(Unit,entry => run(entry))
    T.expect_error(Unit,93,V.Entry.with(Unit,entry => abandon(entry)))
    live : U32 <- V.debug_live_objects()
    Demo.require(U32.is_eq(live,0),"Graphics success/failure scopes leaked")

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- all_checks()
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Indexed acceptance leaked")
    V.or_exit(Unit,checked)
