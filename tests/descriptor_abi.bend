import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W

def probe(bindings: List<V.DescriptorBinding>, pool: V.DescriptorPoolCreateInfo, writes: List<V.DescriptorWrite>, sampler: V.SamplerCreateInfo, layout: V.PipelineLayoutCreateInfo, canonical: List<V.DescriptorBinding>) -> IO(Unit):
  import "./descriptor_abi.c"

def main() -> IO(Unit):
  probe([V.DescriptorBinding{9,V.SampledDescriptor{},2,16},V.DescriptorBinding{3,V.UniformDescriptor{},4,17}],
    V.DescriptorPoolCreateInfo{7,[V.DescriptorPoolSize{V.UniformDescriptor{},11},V.DescriptorPoolSize{V.SampledDescriptor{},13}]},
    [V.UniformWrite{3,1,[V.DescriptorBuffer{V.Buffer{23},W.U64{305419896,2596069104},W.U64{7,1}}]},V.SampledWrite{9,0,[V.DescriptorImage{V.ImageView{29},V.Sampler{31},4}]}],
    V.SamplerCreateInfo{1,0,1,2,3,4,0.25,3.5,5},V.PipelineLayoutCreateInfo{[V.DescriptorSetLayout{37},V.DescriptorSetLayout{41}],Some{V.PushConstantRange{17,64}}},
    V.descriptor_schema([V.DescriptorBinding{9,V.SampledDescriptor{},2,16},V.DescriptorBinding{3,V.UniformDescriptor{},4,17}]))
