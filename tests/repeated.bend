import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./transfers.bend as Transfer
import ./native.bend as T
import ./array_rejection.bend as A

type Resources is Data:
  Resources{device: V.Device, pool: V.CommandPool, command: V.CommandBuffer, spare: V.CommandBuffer, fence: V.Fence, spare_fence: V.Fence, staging: V.Buffer, staging_memory: V.DeviceMemory, gpu: V.Buffer, readback: V.Buffer, readback_memory: V.DeviceMemory, guard: V.Buffer, unrelated: V.DeviceMemory}

def payload(alternate: Bool) -> Array<U32>:
  match alternate:
    case False{}:
      A.words()
    case True{}:
      a = [0 : U32*4n]
      a[0] <- 286397204
      a[1] <- 404166165
      a[2] <- 471538201
      a[3] <- 538910237
      a

def expected(alternate: Bool) -> List<U32>:
  match alternate:
    case False{}:
      [4,3,2,1,5,6,7]
    case True{}:
      [20,19,18,17,21,22,23]

def upload_result(owned: Array<U32> & V.VkResult(Unit), alternate: Bool) -> V.Action(Unit):
  (words, result) = owned
  do V.Action<Unit>:
    Demo.require(Demo.bytes_equal(Array.to_list(~U32, words), Array.to_list(~U32, payload(alternate))), "Repeated upload changed words")
    A.result_code(0, result)

def upload(+device: V.Device, memory: V.DeviceMemory, +alternate: Bool) -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    owned : Array<U32> & V.VkResult(Unit) <- V.Device.write_memory_words(device, memory, W.of_u32(3), W.of_u32(7), payload(alternate))
    upload_result(owned, alternate)

def poll(fuel: Nat, +fence: V.Fence, status: U32) -> V.Action(Unit):
  match fuel:
    case 0n:
      Demo.require(U32.is_eq(status,0), "Bounded status polling did not complete")
    case 1n+p:
      match status:
        case 0:
          V.Action.pure(Unit, Unit{})
        case _:
          do V.Action<Unit>:
            next : U32 <- V.Fence.status(fence)
            poll(p, fence, next)

def complete(mode: U32, +device: V.Device, +fence: V.Fence) -> V.Action(Unit):
  match mode:
    case 0:
      do V.Action<Unit>:
        status : U32 <- V.Fence.wait(fence, W.of_u32(1000000000))
        Demo.require(U32.is_eq(status,0), "Finite GPU completion wait timed out")
    case 1:
      do V.Action<Unit>:
        status : U32 <- V.Fence.status(fence)
        poll(100000n, fence, status)
    case _:
      V.Device.wait_idle(device)

def pending_checks(resources: Resources) -> V.Action(Unit):
  Resources{+device,+pool,+command,+spare,+fence,+spare_fence,+staging,+staging_memory,gpu,+readback,+readback_memory,guard,+unrelated} = resources
  do V.Action<Unit>:
    T.expect_error(Unit, 1610612740, V.Device.submit(device, spare, spare_fence))
    T.expect_error(Unit, 1610612740, V.Device.submit_and_wait(device, spare))
    T.expect_error(Unit, 1610612740, V.CommandBuffer.reset(command))
    T.expect_error(Unit, 1610612740, V.Device.destroy_command_pool(device, pool))
    T.expect_error(Unit, 1610612740, V.Fence.reset(fence))
    T.expect_error(Unit, 1610612740, V.Device.destroy_fence(device, fence))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, staging))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, readback))
    T.expect_error(List<U32>, 1610612740, V.Device.read_memory(device, staging_memory, W.zero(), 1))
    T.expect_error(Unit, 1610612740, V.Device.write_memory(device, readback_memory, W.zero(), [0]))
    Transfer.upload(device, staging_memory, W.zero(), W.of_u32(1), 1610612740)
    V.Device.write_memory(device, unrelated, W.zero(), [91])
    bytes : List<U32> <- V.Device.read_memory(device, unrelated, W.zero(), 1)
    Demo.require(Demo.bytes_equal(bytes,[91]), "Unrelated memory was blocked")

def cycle(+resources: Resources, +alternate: Bool, mode: U32) -> V.Action(Unit):
  Resources{+device,pool,+command,spare,+fence,spare_fence,+staging,+staging_memory,+gpu,+readback,+readback_memory,+guard,unrelated} = resources
  do V.Action<Unit>:
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    upload(device, staging_memory, alternate)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.copy_buffer(command, staging, gpu, [V.BufferCopy{W.of_u32(3), W.of_u32(5), W.of_u32(7)}])
    V.CommandBuffer.pipeline_barrier(command, 4096, 4096, [], [V.BufferMemoryBarrier{gpu,W.of_u32(5),W.of_u32(7),4096,2048},V.BufferMemoryBarrier{guard,W.zero(),Core.whole_size(),0,0}])
    V.CommandBuffer.copy_buffer(command, gpu, readback, [V.BufferCopy{W.of_u32(5),W.of_u32(9),W.of_u32(7)}])
    V.CommandBuffer.pipeline_barrier(command, 4096, 16384, [V.MemoryBarrier{4096,8192}], [])
    V.CommandBuffer.end(command)
    V.Device.submit(device, command, fence)
    pending_checks(resources)
    complete(mode, device, fence)
    bytes : List<U32> <- V.Device.read_memory(device, readback_memory, W.of_u32(9), 7)
    Demo.require(Demo.bytes_equal(bytes,expected(alternate)), "Repeated GPU literal readback mismatch")
    T.expect_error(Unit, 1610612740, V.Device.submit(device, command, fence))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, staging))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, readback))
    T.expect_error(Unit, 1610612740, V.Device.destroy_buffer(device, guard))

def cycles(fuel: Nat, +resources: Resources, +alternate: Bool, +mode: U32, +rows: U32) -> V.Action(Unit):
  match fuel:
    case 0n:
      V.Action.pure(Unit, Unit{})
    case 1n+p:
      do V.Action<Unit>:
        cycle(resources, alternate, mode)
        live : U32 <- V.debug_live_objects()
        Demo.require(U32.is_eq(live,rows), "Registry grew during reused transfers")
        cycles(p, resources, Bool.not(alternate), U32.mod(U32.inc(mode),3), rows)

def convenience_cycles(fuel: Nat, +device: V.Device, +command: V.CommandBuffer, +rows: U32) -> V.Action(Unit):
  match fuel:
    case 0n:
      V.Action.pure(Unit, Unit{})
    case 1n+p:
      do V.Action<Unit>:
        V.CommandBuffer.reset(command)
        V.CommandBuffer.begin(command)
        V.CommandBuffer.end(command)
        V.Device.submit_and_wait(device, command)
        live : U32 <- V.debug_live_objects()
        Demo.require(U32.is_eq(live,rows), "Private convenience fence was reallocated")
        convenience_cycles(p,device,command,rows)

def exercise(+device: V.Device, source: V.Buffer & V.DeviceMemory, middle: V.Buffer & V.DeviceMemory, destination: V.Buffer & V.DeviceMemory, barrier: V.Buffer & V.DeviceMemory, +unrelated: V.DeviceMemory) -> V.Action(Unit):
  (+src,+sm) = source
  (+gpu,gm) = middle
  (+dst,+rm) = destination
  (+guard,guard_memory) = barrier
  do V.Action<Unit>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +spare : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    +spare_fence : V.Fence <- V.Device.create_fence(device,True{})
    ready : U32 <- V.Fence.status(spare_fence)
    Demo.require(U32.is_eq(ready,0), "Initially signaled fence")
    high : U32 <- V.Fence.wait(spare_fence,W.U64{0,1})
    Demo.require(U32.is_eq(high,0), "High timeout limb")
    maximum : U32 <- V.Fence.wait(spare_fence,Core.whole_size())
    Demo.require(U32.is_eq(maximum,0), "Maximum timeout")
    V.CommandBuffer.begin(spare)
    V.CommandBuffer.end(spare)
    T.expect_error(Unit,1610612740,V.Device.submit(device,spare,spare_fence))
    V.Fence.reset(spare_fence)
    not_ready : U32 <- V.Fence.status(fence)
    Demo.require(U32.is_eq(not_ready,1), "Never-submitted fence NOT_READY")
    zero : U32 <- V.Fence.wait(fence,W.zero())
    Demo.require(U32.is_eq(zero,2), "Never-submitted zero TIMEOUT")
    finite : U32 <- V.Fence.wait(fence,W.of_u32(1000))
    Demo.require(U32.is_eq(finite,2), "Never-submitted finite TIMEOUT")
    +resources : Resources = Resources{device,pool,command,spare,fence,spare_fence,src,sm,gpu,dst,rm,guard,unrelated}
    rows : U32 <- V.debug_live_objects()
    cycles(32n,resources,False{},0,rows)
    V.CommandBuffer.reset(command)
    V.CommandBuffer.reset(command)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.reset(command)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.end(command)
    V.Device.submit_and_wait(device,command)
    stable : U32 <- V.debug_live_objects()
    convenience_cycles(32n,device,command,stable)
    V.CommandBuffer.reset(command)
    V.Device.destroy_buffer(device,src)
    V.Device.destroy_buffer(device,dst)
    V.Device.destroy_buffer(device,guard)
    V.Device.destroy_fence(device,fence)
    T.expect_error(U32,1610612738,V.Fence.status(fence))
    T.expect_error(Unit,1610612738,V.Fence.reset(fence))
    V.Device.destroy_command_pool(device,pool)

def with_guard(+instance: V.Instance,+physical: V.PhysicalDevice,+device: V.Device,source: V.Buffer & V.DeviceMemory,middle: V.Buffer & V.DeviceMemory,destination: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  do V.Action<Unit>:
    guard : V.Buffer & V.DeviceMemory <- Transfer.buffer(instance,physical,device,3,2)
    +probe : V.Buffer <- V.Device.create_buffer(device,V.BufferCreateInfo{W.of_u32(64),3})
    req : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,probe)
    unrelated : V.DeviceMemory <- Transfer.allocate(instance,physical,device,req,2)
    V.Device.destroy_buffer(device,probe)
    exercise(device,source,middle,destination,guard,unrelated)

def with_destination(+instance: V.Instance,+physical: V.PhysicalDevice,+device: V.Device,source: V.Buffer & V.DeviceMemory,middle: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  do V.Action<Unit>:
    destination : V.Buffer & V.DeviceMemory <- Transfer.buffer(instance,physical,device,3,2)
    with_guard(instance,physical,device,source,middle,destination)

def with_middle(+instance: V.Instance,+physical: V.PhysicalDevice,+device: V.Device,source: V.Buffer & V.DeviceMemory) -> V.Action(Unit):
  do V.Action<Unit>:
    middle : V.Buffer & V.DeviceMemory <- Transfer.buffer(instance,physical,device,3,1)
    with_destination(instance,physical,device,source,middle)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- Demo.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    source : V.Buffer & V.DeviceMemory <- Transfer.buffer(instance,physical,device,3,2)
    with_middle(instance,physical,device,source)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    check : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Repeated scope leaked")
    V.or_exit(Unit,check)
    IO.print("32 repeated GPU transfers and 32 private-fence reuses passed")
