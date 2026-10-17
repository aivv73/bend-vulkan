import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as S
import ../examples/indexed_offscreen.bend as E
import ../examples/buffer_roundtrip.bend as D
import ./native.bend as T

type Fixture is Data:
  Fixture{device: V.Device, command: V.CommandBuffer, fence: V.Fence, pool: V.DescriptorPool, uniform: V.DescriptorSet, sampled: V.DescriptorSet, um: V.DeviceMemory, vm: V.DeviceMemory, ub: V.Buffer, vb: V.Buffer, sampler: V.Sampler, a: E.Attachment, b: E.Attachment, color: E.Attachment, stage: E.BoundBuffer, af: V.Framebuffer, bf: V.Framebuffer, cf: V.Framebuffer, depth_pipeline: V.GraphicsPipeline, color_pipeline: V.GraphicsPipeline, index: V.Buffer}

def uniform_schema() -> V.DescriptorSetLayoutCreateInfo:
  V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{3,V.UniformDescriptor{},2,17},V.DescriptorBinding{0,V.UniformDescriptor{},1,17}]}

def uniform_writes(ub: V.Buffer, +vb: V.Buffer) -> List<V.DescriptorWrite>:
  [V.UniformWrite{3,0,[V.DescriptorBuffer{ub,W.zero(),W.of_u32(16)},V.DescriptorBuffer{vb,W.zero(),W.of_u32(16)}]},V.UniformWrite{0,0,[V.DescriptorBuffer{vb,W.zero(),W.of_u32(16)}]}]

def sample_writes(a: E.Attachment, b: E.Attachment, +sampler: V.Sampler) -> List<V.DescriptorWrite>:
  E.Attachment{ai,am,av} = a
  E.Attachment{bi,bm,bv} = b
  [V.SampledWrite{9,0,[V.DescriptorImage{av,sampler,4},V.DescriptorImage{bv,sampler,4}]}]

def pipeline(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, +depth: Bool) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,S.descriptor_vertex_words())
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,Bool.pick(List<U32>,depth,S.descriptor_depth_words(),S.descriptor_fragment_words()))
    result : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[],[],3,V.RasterState{0,0},Bool.pick(Maybe<&2,V.DepthState>,depth,Some{V.DepthState{True{},True{},7}},None{}),15})
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    return result

def depth_framebuffer(device: V.Device, pass: V.RenderPass, a: E.Attachment) -> V.Action(V.Framebuffer):
  E.Attachment{image,memory,view} = a
  V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view],V.Extent2D{8,4}})

def color_framebuffer(device: V.Device, pass: V.RenderPass, a: E.Attachment) -> V.Action(V.Framebuffer):
  E.Attachment{image,memory,view} = a
  V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[view],V.Extent2D{8,4}})

def buffer_handle(buffer: E.BoundBuffer) -> V.Buffer:
  E.BoundBuffer{handle,memory} = buffer
  handle

def buffer_memory(buffer: E.BoundBuffer) -> V.DeviceMemory:
  E.BoundBuffer{handle,memory} = buffer
  memory

def uniform_initialize(+device: V.Device, u: E.BoundBuffer, v: E.BoundBuffer, i: E.BoundBuffer) -> V.Action(Unit):
  E.BoundBuffer{ub,um} = u
  E.BoundBuffer{vb,vm} = v
  E.BoundBuffer{ib,im} = i
  do V.Action<Unit>:
    V.Device.write_memory(device,um,W.zero(),E.bytes([1048576000,0,0,0]))
    V.Device.write_memory(device,vm,W.zero(),E.bytes([0,1048576000,0,0]))
    V.Device.write_memory(device,im,W.zero(),E.bytes([0,1,2]))

def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Fixture):
  do V.Action<Fixture>:
    +a : E.Attachment <- E.attachment(instance,physical,device,126,2,37)
    +b : E.Attachment <- E.attachment(instance,physical,device,126,2,37)
    +color : E.Attachment <- E.attachment(instance,physical,device,37,1,17)
    +uniform_buffer : E.BoundBuffer <- E.buffer(instance,physical,device,16,16)
    +value_buffer : E.BoundBuffer <- E.buffer(instance,physical,device,16,16)
    +index_buffer : E.BoundBuffer <- E.buffer(instance,physical,device,16,64)
    +stage : E.BoundBuffer <- E.buffer(instance,physical,device,128,2)
    uniform_initialize(device,uniform_buffer,value_buffer,index_buffer)
    +ub : V.Buffer = buffer_handle(uniform_buffer)
    +vb : V.Buffer = buffer_handle(value_buffer)
    um : V.DeviceMemory = buffer_memory(uniform_buffer)
    vm : V.DeviceMemory = buffer_memory(value_buffer)
    index : V.Buffer = buffer_handle(index_buffer)
    +schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,uniform_schema())
    +equivalent : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{0,V.UniformDescriptor{},1,17},V.DescriptorBinding{3,V.UniformDescriptor{},2,17}]})
    +sample_schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{9,V.SampledDescriptor{},2,16}]})
    +pool : V.DescriptorPool <- V.Device.create_descriptor_pool(device,V.DescriptorPoolCreateInfo{2,[V.DescriptorPoolSize{V.UniformDescriptor{},3},V.DescriptorPoolSize{V.SampledDescriptor{},2}]})
    +uniform : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,schema)
    +sampled : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,sample_schema)
    V.Device.update_descriptor_set(device,uniform,uniform_writes(ub,vb))
    T.expect_error(Unit,1610612740,V.Device.destroy_descriptor_set_layout(device,schema))
    +sampler : V.Sampler <- V.Device.create_sampler(device,V.SamplerCreateInfo{0,0,0,2,2,2,0.0,0.0,4})
    V.Device.update_descriptor_set(device,sampled,sample_writes(a,b,sampler))
    T.expect_error(Unit,1610612740,V.Device.destroy_sampler(device,sampler))
    +dl : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[equivalent],None{}})
    +cl : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[equivalent,sample_schema],None{}})
    +dp : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[],Some{V.AttachmentInfo{126,1,0}}})
    +cp : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],None{}})
    +af : V.Framebuffer <- depth_framebuffer(device,dp,a)
    +bf : V.Framebuffer <- depth_framebuffer(device,dp,b)
    +cf : V.Framebuffer <- color_framebuffer(device,cp,color)
    depth_pipeline : V.GraphicsPipeline <- pipeline(device,dl,dp,True{})
    color_pipeline : V.GraphicsPipeline <- pipeline(device,cl,cp,False{})
    +commands : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,commands)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Fixture{device,command,fence,pool,uniform,sampled,um,vm,ub,vb,sampler,a,b,color,stage,af,bf,cf,depth_pipeline,color_pipeline,index}

def state(+command: V.CommandBuffer, index: V.Buffer) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,8.0,4.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,E.area())
    V.CommandBuffer.bind_index_buffer(command,index,W.zero(),1)

def depth(+f: Fixture, attachment: E.Attachment, framebuffer: V.Framebuffer) -> V.Action(Unit):
  Fixture{+device,+command,+fence,pool,+uniform,sampled,um,vm,ub,vb,sampler,a,b,color,stage,af,bf,cf,depth_pipeline,color_pipeline,+index} = f
  E.Attachment{+image,memory,view} = attachment
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,136,[V.MemoryBarrier{16384,8}],[],[])
    E.transition(command,image,2,0,3,1,768,0,1536)
    V.CommandBuffer.begin_render_pass(command,framebuffer,E.area(),[V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,depth_pipeline)
    V.CommandBuffer.bind_descriptor_sets(command,0,[uniform])
    state(command,index)
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{3,1,0,V.BaseVertex{0},0})
    T.expect_error(Unit,1610612740,V.Device.update_descriptor_set(device,uniform,uniform_writes(ub,vb)))
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,image,2,3,4,768,128,1024,32)
    E.complete(device,command,fence)
    E.reset(device,command,fence)

def expected(count: Nat, +rewrite: Bool) -> List<U32>:
  match count:
    case 0n: []
    case 1n+rest:
      List.append(&1,U32,Bool.pick(List<U32>,rewrite,[255,191,64,255],[64,64,191,255]),expected(rest,rewrite))

def check_bytes(actual: List<U32>, expected: List<U32>) -> V.Action(Unit):
  D.require(D.bytes_equal(actual,expected),"Literal uniform and rendered depth array sampling mismatch")

def render(+f: Fixture, +rewrite: Bool, +initialized: Bool) -> V.Action(Unit):
  Fixture{+device,+command,+fence,+pool,+uniform,+sampled,+um,+vm,ub,vb,sampler,a,b,E.Attachment{+color,cm,cv},E.BoundBuffer{+stage,+sm},af,bf,cf,depth_pipeline,+color_pipeline,+index} = f
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,136,[V.MemoryBarrier{16384,8}],[],[])
    E.transition(command,color,1,Bool.pick(U32,initialized,6,0),2,Bool.pick(U32,initialized,4096,1),1024,Bool.pick(U32,initialized,2048,0),256)
    V.CommandBuffer.begin_render_pass(command,cf,E.area(),[V.ColorClear{V.ClearColor{0.0,0.0,0.0,0.0}}])
    V.CommandBuffer.bind_graphics_pipeline(command,color_pipeline)
    state(command,index)
    T.expect_error(Unit,1610612740,V.CommandBuffer.draw_indexed(command,V.IndexedDraw{3,1,0,V.BaseVertex{0},0}))
    V.CommandBuffer.bind_descriptor_sets(command,0,[uniform,sampled])
    V.CommandBuffer.bind_graphics_pipeline(command,color_pipeline)
    T.expect_error(Unit,1610612740,V.CommandBuffer.draw_indexed(command,V.IndexedDraw{3,1,0,V.BaseVertex{0},0}))
    V.CommandBuffer.bind_descriptor_sets(command,0,[uniform,sampled])
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{3,1,0,V.BaseVertex{0},0})
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    V.CommandBuffer.copy_image_to_buffer(command,color,6,stage,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{8,4}}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    V.CommandBuffer.end(command)
    T.expect_error(Unit,1610612740,V.Device.reset_descriptor_pool(device,pool))
    V.Device.submit(device,command,fence)
    T.expect_error(Unit,1610612740,V.Device.write_memory(device,um,W.zero(),[0]))
    T.expect_error(List<U32>,1610612740,V.Device.read_memory(device,vm,W.zero(),1))
    completed : U32 <- V.Fence.wait(fence,Core.whole_size())
    D.require(U32.is_zero(completed),"Descriptor GPU fence incomplete")
    T.expect_error(Unit,1610612740,V.Device.free_descriptor_set(device,sampled))
    T.expect_error(Unit,1610612740,V.Device.update_descriptor_set(device,uniform,uniform_writes(ub,vb)))
    bytes : List<U32> <- V.Device.read_memory(device,sm,W.zero(),128)
    check_bytes(bytes,expected(32n,rewrite))
    E.reset(device,command,fence)

def failed_rewrite(enabled: U32, +f: Fixture) -> V.Action(Unit):
  match enabled:
    case 0: V.Action.pure(Unit,Unit{})
    case _:
      Fixture{+device,command,fence,pool,+uniform,+sampled,um,vm,+ub,+vb,+sampler,+a,+b,color,stage,af,bf,cf,dp,cp,index} = f
      do V.Action<Unit>:
        armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(3735928557))
        T.expect_error(Unit,1610612741,V.Device.update_descriptor_set(device,sampled,sample_writes(b,a,sampler)))
        render(f,False{},True{})
        armed_again : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(3735928557))
        T.expect_error(Unit,1610612741,V.Device.update_descriptor_set(device,uniform,uniform_writes(vb,ub)))
        render(f,False{},True{})
        V.Action.lift(Unit,IO.print("Literal GPU readback after injected sampled and uniform rewrite OOM passed"))

def failure_check(flag: U32 & U32, f: Fixture) -> V.Action(Unit):
  (low,high) = flag
  failed_rewrite(high,f)

def exercise(+f: Fixture) -> V.Action(Unit):
  Fixture{+device,command,fence,+pool,+uniform,+sampled,um,+vm,+ub,+vb,+sampler,+a,+b,color,stage,+af,+bf,cf,depth_pipeline,color_pipeline,index} = f
  do V.Action<Unit>:
    depth(f,a,af)
    V.Device.write_memory(device,um,W.zero(),E.bytes([1061158912,0,0,0]))
    depth(f,b,bf)
    render(f,False{},False{})
    flag : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(3735928556))
    failure_check(flag,f)
    V.Device.update_descriptor_set(device,sampled,sample_writes(b,a,sampler))
    V.Device.update_descriptor_set(device,uniform,uniform_writes(vb,ub))
    V.Device.write_memory(device,um,W.zero(),E.bytes([1061158912,1065353216,0,0]))
    render(f,True{},True{})
    V.Device.free_descriptor_set(device,uniform)
    V.Device.reset_descriptor_pool(device,pool)
    T.expect_error(Unit,1610612738,V.Device.free_descriptor_set(device,sampled))
    V.Device.destroy_descriptor_pool(device,pool)
    V.Action.lift(Unit,IO.print("Literal uniform and rendered D32 sampling, arrays, sparse equivalent schemas and rewrites passed"))

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    fixture : Fixture <- create(instance,physical,device)
    exercise(fixture)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Descriptor scope leaked rows")
    V.or_exit(Unit,checked)
