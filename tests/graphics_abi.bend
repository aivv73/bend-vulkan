import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W

def probe(info: V.GraphicsPipelineCreateInfo, empty: V.GraphicsPipelineCreateInfo, layout: V.PipelineLayoutCreateInfo, no_push: V.PipelineLayoutCreateInfo, viewport: V.Viewport, draw: V.IndexedDraw, minimum: V.BaseVertex, offset: W.U64, words: List<U32>) -> IO(Unit):
  import "./graphics_abi.c"

def main() -> IO(Unit):
  probe(V.GraphicsPipelineCreateInfo{V.PipelineLayout{11},V.RenderPass{13},V.ShaderModule{17},V.ShaderModule{19},[V.VertexInputBinding{7,24,1}],[V.VertexInputAttribute{3,7,106,12}],3,V.RasterState{2,1},Some{V.DepthState{True{},False{},6}},15},
    V.GraphicsPipelineCreateInfo{V.PipelineLayout{23},V.RenderPass{29},V.ShaderModule{31},V.ShaderModule{37},[],[],4,V.RasterState{0,0},None{},7},
    V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{17,128}}},V.PipelineLayoutCreateInfo{[],None{}},
    V.Viewport{F32.neg(0.5),0.25,32.0,64.0,0.0,1.0},V.IndexedDraw{6,2,3,V.BaseVertex{4294967293},5},V.BaseVertex{2147483648},W.U64{305419896,2596069104},[119734787,4294967295])
