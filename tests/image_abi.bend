import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W

def probe(color: V.ClearColor, clears: List<V.ClearValue>, pass: V.RenderPassCreateInfo, empty: V.RenderPassCreateInfo, framebuffer: V.FramebufferCreateInfo, copy: V.BufferImageCopy, barrier: V.ImageMemoryBarrier, create: V.ImageCreateInfo, view: V.ImageViewCreateInfo, configuration: V.ImageFormatInfo, area: V.RenderArea, properties: V.ImageFormatProperties, depth: F32) -> IO(Unit):
  import "./image_abi.c"

def main() -> IO(Unit):
  probe(V.ClearColor{0.25, F32.neg(0.5), 1.0, F32.neg(0.0)},
    [V.ColorClear{V.ClearColor{0.25,F32.neg(0.5),1.0,F32.neg(0.0)}},V.DepthClear{0.5},V.UnusedClear{}],
    V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,2,1}}},
    V.RenderPassCreateInfo{[],None{}},
    V.FramebufferCreateInfo{V.RenderPass{17},[V.ImageView{19}],V.Extent2D{23,29}},
    V.BufferImageCopy{W.U64{305419896,2596069104},31,37,V.ImageSubresourceLayers{1,2,3,4},V.Offset2D{41,43},V.Extent2D{47,53}},
    V.ImageMemoryBarrier{V.ImageHandle{59},V.ImageSubresourceRange{1,2,3,4,5},6,7,8,9},
    V.ImageCreateInfo{37,V.Extent2D{61,67},3,2,7},
    V.ImageViewCreateInfo{V.ImageHandle{71},1,V.ImageSubresourceRange{1,2,3,4,5}},
    V.ImageFormatInfo{37,1,0,3,0},V.RenderArea{V.Offset2D{73,79},V.Extent2D{83,89}},
    V.ImageFormatProperties{1,2,3,4,5,6,W.U64{305419896,2596069104}},0.5)
