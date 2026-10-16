import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as D
import ../examples/indexed_offscreen.bend as E
import ./native.bend as T

def transfer(+device: V.Device, source: E.BoundBuffer, destination: E.BoundBuffer) -> V.Action(Unit):
  E.BoundBuffer{+src,sm} = source
  E.BoundBuffer{+dst,+dm} = destination
  do V.Action<Unit>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +first : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +second : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    +signal : V.Semaphore <- V.Device.create_semaphore(device)
    V.CommandBuffer.begin(first)
    V.CommandBuffer.fill_buffer(first,src,W.zero(),W.of_u32(16),16909060)
    V.CommandBuffer.end(first)
    T.expect_error(Unit,1610612740,V.Device.submit_synced(device,first,fence,[V.SemaphoreWait{signal,4096}],[]))
    T.expect_error(Unit,1610612739,V.Device.submit_synced(device,first,fence,[],[signal,signal]))
    T.expect_error(Unit,1610612738,V.Device.submit_synced(device,first,fence,[],[V.Semaphore{4294967295}]))
    V.Device.submit_synced(device,first,fence,[],[signal])
    T.expect_error(Unit,1610612740,V.Device.destroy_semaphore(device,signal))
    completed : U32 <- V.Fence.wait(fence,Core.whole_size())
    D.require(U32.is_zero(completed),"Semaphore signal submission did not complete")
    V.Fence.reset(fence)
    V.CommandBuffer.begin(second)
    V.CommandBuffer.copy_buffer(second,src,dst,[V.BufferCopy{W.zero(),W.zero(),W.of_u32(16)}])
    V.CommandBuffer.pipeline_barrier(second,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    V.CommandBuffer.end(second)
    T.expect_error(Unit,1610612740,V.Device.submit_synced(device,second,fence,[V.SemaphoreWait{signal,0}],[]))
    T.expect_error(Unit,1610612739,V.Device.submit_synced(device,second,fence,[V.SemaphoreWait{signal,4096}],[signal]))
    V.Device.submit_synced(device,second,fence,[V.SemaphoreWait{signal,4096}],[])
    observed : U32 <- V.Fence.wait(fence,Core.whole_size())
    D.require(U32.is_zero(observed),"Semaphore wait submission did not complete")
    bytes : List<U32> <- V.Device.read_memory(device,dm,W.zero(),16)
    D.require(D.bytes_equal(bytes,[4,3,2,1,4,3,2,1,4,3,2,1,4,3,2,1]),"Semaphore signal-to-wait readback mismatch")
    V.Device.destroy_semaphore(device,signal)
    T.expect_error(Unit,1610612738,V.Device.destroy_semaphore(device,signal))
    V.Action.lift(Unit,IO.print("Binary semaphore signal-to-wait literal GPU readback passed"))

def buffers(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Unit):
  do V.Action<Unit>:
    source : E.BoundBuffer <- E.buffer(instance,physical,device,16,3)
    destination : E.BoundBuffer <- E.buffer(instance,physical,device,16,3)
    transfer(device,source,destination)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    buffers(instance,physical,device)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
