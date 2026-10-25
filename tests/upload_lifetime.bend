import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/upload.bend as Upload
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as D
import ./transfers.bend as T
import ./native.bend as N
import ./array_rejection.bend as A

def reserved(pair: Upload.Staging & V.VkResult(Unit)) -> V.Action(Upload.Staging):
  (staging,result) = pair
  do V.Action<Upload.Staging>:
    IO.pure(V.VkResult(Unit),result)
    return staging

def staged(pair: (Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice)) -> V.Action(Upload.Staging & Upload.Slice):
  ((staging,words),result) = pair
  do V.Action<Upload.Staging & Upload.Slice>:
    D.require(D.bytes_equal(Array.to_list(~U32,words),[16909060,134678021,202050057,269422093]),"Staging changed the source array")
    slice : Upload.Slice <- IO.pure(V.VkResult(Upload.Slice),result)
    return (staging,slice)

def owner_is(staging: Upload.Staging, buffer: V.Buffer) -> Bool:
  match staging buffer:
    case Upload.Staging{Upload.Allocation{V.Buffer{actual},memory,W.U64{128,0}},W.U64{0,0}} V.Buffer{expected}: U32.is_eq(actual,expected)
    case _ _: False{}

def grow_rejected(expected: V.Buffer, pair: Upload.Staging & V.VkResult(Unit)) -> V.Action(Upload.Staging):
  (+staging,result) = pair
  do V.Action<Upload.Staging>:
    A.result_code(1610612740,result)
    D.require(owner_is(staging,expected),"Failed staging growth changed the original allocation owner")
    return staging

def retained(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +pool: V.CommandPool, +command: V.CommandBuffer, +spare: V.CommandBuffer, +fence: V.Fence, +staging: Upload.Staging, slice: Upload.Slice, target: V.Buffer & V.DeviceMemory, readback: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  Upload.Slice{+source,offset,length} = slice
  (+buffer,+memory) = target
  (+output,+output_memory) = readback
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.copy_buffer(command,source,buffer,[V.BufferCopy{offset,W.zero(),length}])
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[],[V.BufferMemoryBarrier{buffer,W.zero(),W.of_u32(7),4096,2048}],[])
    V.CommandBuffer.copy_buffer(command,buffer,output,[V.BufferCopy{W.zero(),W.zero(),W.of_u32(7)}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    +growth_rows : U32 <- V.debug_live_objects()
    growth : Upload.Staging & V.VkResult(Unit) <- V.Action.lift(Upload.Staging & V.VkResult(Unit),Upload.reserve(instance,physical,device,Upload.reset(staging),W.of_u32(256)))
    +kept : Upload.Staging <- grow_rejected(source,growth)
    after_growth : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(growth_rows,after_growth),"Failed staging growth leaked its replacement allocation")
    V.CommandBuffer.end(command)
    V.CommandBuffer.begin(spare)
    V.CommandBuffer.fill_buffer(spare,buffer,W.zero(),W.of_u32(4),0)
    N.expect_error(Unit,1610612740,V.Device.retire_buffers(device,[(buffer,memory)]))
    V.CommandBuffer.end(spare)
    +before : U32 <- V.debug_live_objects()
    V.Device.submit(device,command,fence)
    V.Device.retire_buffers(device,[(buffer,memory)])
    V.Device.retire_buffers(device,[(buffer,memory)])
    V.Device.collect_retired(device)
    during : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(before,during),"Retired pending geometry disappeared")
    complete : U32 <- V.Fence.wait(fence,W.of_u32(1000000000))
    D.require(U32.is_zero(complete),"Upload completion timed out")
    bytes : List<U32> <- V.Device.read_memory(device,output_memory,W.zero(),7)
    D.require(D.bytes_equal(bytes,[1,5,6,7,8,9,10]),"Staged source subrange did not reach the device literally")
    V.Device.collect_retired(device)
    completed : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(before,completed),"Completion released retained command references")
    V.Fence.reset(fence)
    N.expect_error(Unit,1610612740,V.Device.submit(device,spare,fence))
    V.CommandBuffer.reset(command)
    V.Device.collect_retired(device)
    referenced : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(before,referenced),"Another recording lost retired resources")
    V.CommandBuffer.reset(spare)
    V.Device.collect_retired(device)
    released : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(released,(before - 2 : U32)),"Retired dedicated buffer and memory were not reclaimed after both resets")
    V.CommandBuffer.begin(spare)
    N.expect_error(Unit,1610612738,V.CommandBuffer.fill_buffer(spare,buffer,W.zero(),W.of_u32(4),0))
    V.CommandBuffer.end(spare)
    Upload.release(device,kept)
    V.Device.collect_retired(device)
    V.Device.destroy_command_pool(device,pool)

def transferred(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, pair: Upload.Staging & Upload.Slice) -> V.Action(Unit):
  (+staging,slice) = pair
  do V.Action<Unit>:
    target : V.Buffer & V.DeviceMemory <- T.buffer(instance,physical,device,3,2)
    output : V.Buffer & V.DeviceMemory <- T.buffer(instance,physical,device,3,2)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    spare : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    retained(instance,physical,device,pool,command,spare,fence,staging,slice,target,output)

def stage_error(result: V.VkResult(Upload.Slice)) -> V.Action(Unit):
  match result:
    case Done{slice}: D.require(False{},"Invalid staging source range succeeded")
    case Fail{(code,message)}: D.require(U32.is_eq(code,1610612739),"Invalid staging source range returned the wrong error")

def stage_rejected(pair: (Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice)) -> V.Action(Upload.Staging):
  ((staging,words),result) = pair
  do V.Action<Upload.Staging>:
    D.require(D.bytes_equal(Array.to_list(~U32,words),[16909060,134678021,202050057,269422093]),"Rejected staging lost its array")
    stage_error(result)
    return staging

def prepared(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, staging: Upload.Staging) -> V.Action(Unit):
  do V.Action<Unit>:
    invalid : (Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice) <- V.Action.lift((Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice),Upload.stage(device,staging,W.of_u32(16),W.of_u32(1),A.words()))
    next : Upload.Staging <- stage_rejected(invalid)
    pair : (Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice) <- V.Action.lift((Upload.Staging & Array<U32>) & V.VkResult(Upload.Slice),Upload.stage(device,next,W.of_u32(3),W.of_u32(7),A.words()))
    staged : Upload.Staging & Upload.Slice <- staged(pair)
    transferred(instance,physical,device,staged)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    pair : Upload.Staging & V.VkResult(Unit) <- V.Action.lift(Upload.Staging & V.VkResult(Unit),Upload.reserve(instance,physical,device,Upload.Empty{},W.of_u32(128)))
    staging : Upload.Staging <- reserved(pair)
    prepared(instance,physical,device,staging)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Upload lifetime scope leaked")
    V.or_exit(Unit,checked)
    IO.print("Reusable staging literal source bytes and pending/completed/recorded retirement passed")
