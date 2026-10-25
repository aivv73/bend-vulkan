import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as D
import ../examples/indexed_offscreen.bend as E
import ../src/upload.bend as U
import ./native.bend as N

def buffer(a: U.Allocation) -> V.Buffer:
  U.Allocation{b,m,c} = a
  b

def memory(a: U.Allocation) -> V.DeviceMemory:
  U.Allocation{b,m,c} = a
  m

def unavailable(xs: List<V.Timestamp>) -> V.Action(Unit):
  match xs:
    case [V.Timestamp{W.U64{0,0},False{}},V.Timestamp{W.U64{0,0},False{}}]: V.Action.pure(Unit,Unit{})
    case _: D.require(False{},"Unsubmitted or pending query exposed stale results")

def available(+device: V.Device, bound: W.U64, xs: List<V.Timestamp>) -> V.Action(Unit):
  match xs:
    case [V.Timestamp{start,True{}},V.Timestamp{end,True{}}]:
      do V.Action<Unit>:
        ns : F32 <- V.Device.timestamp_duration(device,start,end,bound)
        D.require((ns >= 0.0 : F32),"Timestamp interval is negative")
    case _: D.require(False{},"Completed timestamp generation was unavailable")

def record(+command: V.CommandBuffer, +pool: V.QueryPool, output: V.Buffer, pattern: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    N.expect_error(Unit,1610612740,V.CommandBuffer.write_timestamp(command,pool,0,1))
    N.expect_error(Unit,1610612739,V.CommandBuffer.reset_timestamp_queries(command,pool,2,1))
    N.expect_error(Unit,1610612739,V.CommandBuffer.reset_timestamp_queries(command,pool,1,4294967295))
    V.CommandBuffer.reset_timestamp_queries(command,pool,0,2)
    N.expect_error(Unit,1610612739,V.CommandBuffer.write_timestamp(command,pool,0,3))
    N.expect_error(Unit,1610612739,V.CommandBuffer.write_timestamp(command,pool,2,1))
    V.CommandBuffer.write_timestamp(command,pool,0,1)
    N.expect_error(Unit,1610612740,V.CommandBuffer.write_timestamp(command,pool,0,1))
    V.CommandBuffer.fill_buffer(command,output,W.zero(),W.of_u32(16),pattern)
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    V.CommandBuffer.write_timestamp(command,pool,1,8192)
    V.CommandBuffer.end(command)

def properties(info: V.TimestampProperties) -> V.Action(Unit):
  V.TimestampProperties{bits,period} = info
  D.require((bits > 0 : U32) && (period > 0.0 : F32),"Actual queue has no timestamp support")

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    info : V.TimestampProperties <- V.Device.timestamp_properties(device)
    properties(info)
    +a : U.Allocation <- U.allocate(instance,physical,device,W.of_u32(16),2,2)
    +b : U.Allocation <- U.allocate(instance,physical,device,W.of_u32(16),2,2)
    +unrelated : U.Allocation <- U.allocate(instance,physical,device,W.of_u32(16),2,2)
    +p1 : V.CommandPool <- V.Device.create_command_pool(device)
    +p2 : V.CommandPool <- V.Device.create_command_pool(device)
    +c1 : V.CommandBuffer <- V.Device.allocate_command_buffer(device,p1)
    +c2 : V.CommandBuffer <- V.Device.allocate_command_buffer(device,p2)
    +spare : V.CommandBuffer <- V.Device.allocate_command_buffer(device,p2)
    +f1 : V.Fence <- V.Device.create_fence(device,False{})
    +f2 : V.Fence <- V.Device.create_fence(device,False{})
    +q1 : V.QueryPool <- V.Device.create_timestamp_pool(device,2)
    +q2 : V.QueryPool <- V.Device.create_timestamp_pool(device,2)
    N.expect_error(List<V.Timestamp>,1610612740,V.Device.timestamp_results(device,q1,0,2))
    +start : W.U64 <- V.monotonic_ns()
    record(c1,q1,buffer(a),67305985)
    record(c2,q2,buffer(b),2289526357)
    V.CommandBuffer.begin(spare)
    N.expect_error(Unit,1610612740,V.CommandBuffer.reset_timestamp_queries(spare,q1,0,2))
    V.CommandBuffer.end(spare)
    before : List<V.Timestamp> <- V.Device.timestamp_results(device,q1,0,2)
    unavailable(before)
    V.Device.submit(device,c1,f1)
    V.Device.submit(device,c2,f2)
    N.expect_error(Unit,1610612740,V.Device.submit(device,spare,f1))
    N.expect_error(Unit,1610612740,V.Device.write_memory(device,memory(a),W.zero(),[0]))
    N.expect_error(Unit,1610612740,V.Device.write_memory(device,memory(b),W.zero(),[0]))
    N.expect_error(List<U32>,1610612740,V.Device.read_memory(device,memory(a),W.zero(),16))
    N.expect_error(List<U32>,1610612740,V.Device.read_memory(device,memory(b),W.zero(),16))
    V.Device.write_memory(device,memory(unrelated),W.zero(),[91])
    other : List<U32> <- V.Device.read_memory(device,memory(unrelated),W.zero(),1)
    D.require(D.bytes_equal(other,[91]),"Independent submissions blocked unrelated host memory")
    N.expect_error(Unit,1610612740,V.Device.destroy_query_pool(device,q1))
    pending : List<V.Timestamp> <- V.Device.timestamp_results(device,q1,0,2)
    unavailable(pending)
    done : U32 <- V.Fence.wait(f1,W.of_u32(1000000000))
    D.require(U32.is_zero(done),"First overlap completion timed out")
    N.expect_error(List<U32>,1610612740,V.Device.read_memory(device,memory(b),W.zero(),16))
    first : List<U32> <- V.Device.read_memory(device,memory(a),W.zero(),16)
    D.require(D.bytes_equal(first,[1,2,3,4,1,2,3,4,1,2,3,4,1,2,3,4]),"First in-flight submission lost its literal bytes")
    +end : W.U64 <- V.monotonic_ns()
    results : List<V.Timestamp> <- V.Device.timestamp_results(device,q1,0,2)
    available(device,W.add(end,W.neg(start)),results)
    N.expect_error(Unit,1610612740,V.Device.destroy_query_pool(device,q1))
    V.Device.wait_idle(device)
    +end2 : W.U64 <- V.monotonic_ns()
    second : List<U32> <- V.Device.read_memory(device,memory(b),W.zero(),16)
    D.require(D.bytes_equal(second,[85,102,119,136,85,102,119,136,85,102,119,136,85,102,119,136]),"Second in-flight submission lost its literal bytes")
    results : List<V.Timestamp> <- V.Device.timestamp_results(device,q2,0,2)
    available(device,W.add(end2,W.neg(start)),results)
    V.CommandBuffer.reset(c1)
    V.Fence.reset(f1)
    V.CommandBuffer.begin(c1)
    V.CommandBuffer.reset_timestamp_queries(c1,q1,0,2)
    stale : List<V.Timestamp> <- V.Device.timestamp_results(device,q1,0,2)
    unavailable(stale)
    V.CommandBuffer.write_timestamp(c1,q1,0,1)
    V.CommandBuffer.write_timestamp(c1,q1,1,8192)
    V.CommandBuffer.end(c1)
    V.Device.submit(device,c1,f1)
    V.Device.wait_idle(device)
    V.CommandBuffer.reset(c1)
    V.CommandBuffer.reset(c2)
    V.CommandBuffer.reset(spare)
    V.Device.destroy_query_pool(device,q1)
    V.Device.destroy_query_pool(device,q2)
    V.Device.destroy_command_pool(device,p1)
    V.Device.destroy_command_pool(device,p2)
    V.Device.destroy_fence(device,f1)
    V.Device.destroy_fence(device,f2)
    U.discard(device,a)
    U.discard(device,b)
    U.discard(device,unrelated)
    V.Device.destroy(device)
    V.Instance.destroy(instance)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Overlap/query scope leaked")
    V.or_exit(Unit,checked)
    IO.print("Two submissions before either fence observation, literal independent readbacks, all-owner host exclusion and query generations passed")
