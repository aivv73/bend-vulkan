import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W

def probe(device: V.PresentationDeviceInfo, swapchain: V.SwapchainCreateInfo, caps: V.SurfaceCapabilities, state: V.WindowSnapshot, acquired: V.AcquireOutcome, out_of_date: V.AcquireOutcome, not_ready: V.AcquireOutcome, timeout: V.AcquireOutcome, lost: V.AcquireOutcome, presented: V.PresentOutcome, suboptimal: V.PresentOutcome, present_out_of_date: V.PresentOutcome, present_lost: V.PresentOutcome, wait: V.SemaphoreWait, timeout_ns: W.U64) -> IO(Unit):
  import "./presentation_abi.c"

def main() -> IO(Unit):
  probe(V.PresentationDeviceInfo{11,13,V.Surface{17}},V.SwapchainCreateInfo{V.Surface{19},3,44,0,V.Extent2D{800,450},16,1,1,2},V.SurfaceCapabilities{2,8,4294967295,4294967295,1,2,4096,8192,1,1,3,16},V.WindowSnapshot{800,450,True{},False{},True{},[Key{119,True{}}]},V.Acquired{V.Acquisition{V.Swapchain{29},W.U64{2309737967,19088743}},7,True{}},V.AcquireOutOfDate{},V.AcquireNotReady{},V.AcquireTimeout{},V.AcquireSurfaceLost{},V.Presented{},V.PresentSuboptimal{},V.PresentOutOfDate{},V.PresentSurfaceLost{},V.SemaphoreWait{V.Semaphore{23},1024},W.U64{2309737967,19088743})
