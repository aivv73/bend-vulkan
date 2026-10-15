import Base
import ../Vulkan.bend as V
import ../shaders/spirv.bend as Shaders
import ../src/core.bend as Core
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T

def info(layout: V.PipelineLayout, pass: V.RenderPass, vertex: V.ShaderModule, fragment: V.ShaderModule) -> V.GraphicsPipelineCreateInfo:
  V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[V.VertexInputBinding{0,24,0}],[V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,106,12}],3,V.RasterState{2,1},Some{V.DepthState{True{},True{},1}},15}

def resources(+instance: V.Instance, +physical: V.PhysicalDevice, +family: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +other : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    T.expect_error(V.ShaderModule,1610612739,V.Device.create_shader_module(device,[]))
    T.expect_error(V.ShaderModule,1610612739,V.Device.create_shader_module(device,[0,65536,0,1,0]))
    T.expect_error(V.PipelineLayout,1610612739,V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{Some{V.PushConstantRange{32,64}}}))
    T.expect_error(V.PipelineLayout,1610612739,V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{Some{V.PushConstantRange{1,132}}}))
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.vertex_words())
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,Shaders.fragment_words())
    +layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{Some{V.PushConstantRange{1,64}}})
    +empty : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{None{}})
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    T.expect_error(V.GraphicsPipeline,1610612738,V.Device.create_graphics_pipeline(other,info(layout,pass,vertex,fragment)))
    +pipeline : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,info(layout,pass,vertex,fragment))
    T.expect_error(Unit,1610612740,V.Device.destroy_pipeline_layout(device,layout))
    T.expect_error(Unit,1610612740,V.Device.destroy_render_pass(device,pass))
    T.expect_error(Unit,1610612738,V.Device.destroy_graphics_pipeline(other,pipeline))
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    T.expect_error(Unit,1610612738,V.Device.destroy_shader_module(device,vertex))
    T.expect_error(V.GraphicsPipeline,1610612738,V.Device.create_graphics_pipeline(device,info(layout,pass,vertex,fragment)))
    V.Device.destroy_graphics_pipeline(device,pipeline)
    V.Device.destroy_pipeline_layout(device,layout)
    V.Device.destroy_pipeline_layout(device,empty)
    V.Device.destroy_render_pass(device,pass)
    V.Device.destroy(other)
    V.Device.destroy(device)
    V.Instance.destroy(instance)
    return Unit{}

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    resources(instance,physical,family)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Graphics resources leaked")
    V.or_exit(Unit,checked)
    IO.print("Real shader/layout/pipeline lifecycle and shader release passed")
