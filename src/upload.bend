import Base
import ../Vulkan.bend as V
import ./core.bend as Core
import ../deps/bend-collections/src/math/u64.bend as W

type Allocation is Data:
  Allocation{buffer: V.Buffer, memory: V.DeviceMemory, capacity: W.U64}
type Staging is Data:
  Empty{}
  Staging{allocation: Allocation, cursor: W.U64}
type Slice is Data:
  Slice{buffer: V.Buffer, offset: W.U64, length: W.U64}

def memory_type(found: Maybe<U32>) -> V.Action(U32):
  match found:
    case None{}: IO.pure(V.VkResult(U32),Fail{(1610612739,"No compatible upload allocation memory type")})
    case Some{index}: V.Action.pure(U32,index)

def memory_requirements(+instance: V.Instance, physical: V.PhysicalDevice, +device: V.Device, required: U32, requirements: V.MemoryRequirements) -> V.Action(V.DeviceMemory):
  V.MemoryRequirements{size,alignment,bits} = requirements
  do V.Action<V.DeviceMemory>:
    types : List<Core.MemoryType> <- V.Instance.get_physical_device_memory_properties(instance,physical)
    index : U32 <- memory_type(Core.find_memory_type(types,bits,required))
    V.Device.allocate_memory(device,size,index)

def memory(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, buffer: V.Buffer, required: U32) -> V.Action(V.DeviceMemory):
  do V.Action<V.DeviceMemory>:
    requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,buffer)
    memory_requirements(instance,physical,device,required,requirements)

def bound(+device: V.Device, +buffer: V.Buffer, +memory: V.DeviceMemory, capacity: W.U64, result: V.VkResult(Unit)) -> V.Action(Allocation):
  match result:
    case Done{unit}: V.Action.pure(Allocation,Allocation{buffer,memory,capacity})
    case Fail{error}:
      do V.Action<Allocation>:
        V.Device.destroy_buffer(device,buffer)
        V.Device.free_memory(device,memory)
        IO.pure(V.VkResult(Allocation),Fail{error})

def allocated(+device: V.Device, +buffer: V.Buffer, capacity: W.U64, result: V.VkResult(V.DeviceMemory)) -> V.Action(Allocation):
  match result:
    case Fail{error}:
      do V.Action<Allocation>:
        V.Device.destroy_buffer(device,buffer)
        IO.pure(V.VkResult(Allocation),Fail{error})
    case Done{+memory}:
      do V.Action<Allocation>:
        result : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),V.Device.bind_buffer_memory(device,buffer,memory,W.zero()))
        bound(device,buffer,memory,capacity,result)

def allocate(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +capacity: W.U64, usage: U32, required: U32) -> V.Action(Allocation):
  do V.Action<Allocation>:
    +buffer : V.Buffer <- V.Device.create_buffer(device,V.BufferCreateInfo{capacity,usage})
    result : V.VkResult(V.DeviceMemory) <- V.Action.lift(V.VkResult(V.DeviceMemory),memory(instance,physical,device,buffer,required))
    allocated(device,buffer,capacity,result)

def retire(+device: V.Device, allocation: Allocation) -> V.Action(Unit):
  Allocation{buffer,memory,capacity} = allocation
  V.Device.retire_buffers(device,[(buffer,memory)])

def release(+device: V.Device, staging: Staging) -> V.Action(Unit):
  match staging:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Staging{allocation,cursor}:
      do V.Action<Unit>:
        retire(device,allocation)
        V.Device.collect_retired(device)

def discard(+device: V.Device, allocation: Allocation) -> V.Action(Unit):
  Allocation{buffer,memory,capacity} = allocation
  do V.Action<Unit>:
    V.Device.destroy_buffer(device,buffer)
    V.Device.free_memory(device,memory)

def retire_old(device: V.Device, staging: Staging) -> V.Action(Unit):
  match staging:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Staging{allocation,cursor}: retire(device,allocation)

def committed(allocation: Allocation, result: V.VkResult(Unit)) -> Staging & V.VkResult(Unit):
  match result:
    case Done{unit}: (Staging{allocation,W.zero()},Done{Unit{}})
    case Fail{(code,message)}: (Staging{allocation,W.zero()},Fail{(code,"Staging growth committed; retired allocation collection failed: " ++ message)})

def retired_old(+device: V.Device, old: Staging, +allocation: Allocation, result: V.VkResult(Unit)) -> IO(Staging & V.VkResult(Unit)):
  match result:
    case Fail{primary}:
      do IO<Staging & V.VkResult(Unit)>:
        cleanup : V.VkResult(Unit) <- discard(device,allocation)
        return (old,V.Entry.finish(Unit,Fail{primary},cleanup))
    case Done{unit}:
      do IO<Staging & V.VkResult(Unit)>:
        cleanup : V.VkResult(Unit) <- V.Device.collect_retired(device)
        return committed(allocation,cleanup)

def reserved(+old: Staging, result: V.VkResult(Allocation), +device: V.Device) -> IO(Staging & V.VkResult(Unit)):
  match result:
    case Fail{error}: IO.pure(Staging & V.VkResult(Unit),(old,Fail{error}))
    case Done{+allocation}:
      do IO<Staging & V.VkResult(Unit)>:
        result : V.VkResult(Unit) <- retire_old(device,old)
        retired_old(device,old,allocation,result)

def grow(needed: Bool, instance: V.Instance, physical: V.PhysicalDevice, +device: V.Device, staging: Staging, capacity: W.U64) -> IO(Staging & V.VkResult(Unit)):
  match needed:
    case False{}: IO.pure(Staging & V.VkResult(Unit),(staging,Done{Unit{}}))
    case True{}:
      do IO<Staging & V.VkResult(Unit)>:
        result : V.VkResult(Allocation) <- allocate(instance,physical,device,capacity,1,2)
        reserved(staging,result,device)

def reserve(instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, staging: Staging, +capacity: W.U64) -> IO(Staging & V.VkResult(Unit)):
  match staging:
    case Empty{}: grow(Bool.not(W.is_zero(capacity)),instance,physical,device,Empty{},capacity)
    case Staging{+allocation,+cursor}:
      Allocation{buffer,memory,+current} = allocation
      match cursor:
        case W.U64{0,0}: grow(Core.size_less(current,capacity),instance,physical,device,Staging{allocation,W.zero()},capacity)
        case _:
          IO.pure(Staging & V.VkResult(Unit),(Staging{allocation,cursor},Fail{(1610612740,"Reset staging cursor before growing storage")}))

def reset(staging: Staging) -> Staging:
  match staging:
    case Empty{}: Empty{}
    case Staging{allocation,cursor}: Staging{allocation,W.zero()}

def chunk(length: W.U64) -> U32:
  W.U64{lo,hi} = length
  Bool.pick(U32,U32.is_zero(hi),U32.min(lo,16777216),16777216)

def fuel_words(length: W.U64) -> Nat:
  W.U64{lo,hi} = length
  1n+Nat.add(U32.to_nat(lo),Nat.mul(U32.to_nat(hi),Nat.mul(65536n,65536n)))

def byte_fuel(length: W.U64) -> Nat:
  fuel_words(W.div_small(W.div_small(length,1048576),16))

def write_next(pair: Array<U32> & V.VkResult(Unit), next: Array<U32> -> IO(Array<U32> & V.VkResult(Unit))) -> IO(Array<U32> & V.VkResult(Unit)):
  (words,result) = pair
  match result:
    case Fail{error}: IO.pure(Array<U32> & V.VkResult(Unit),(words,Fail{error}))
    case Done{unit}: next(words)

def write(fuel: Nat, +device: V.Device, +memory: V.DeviceMemory, +destination: W.U64, +source: W.U64, +length: W.U64, words: Array<U32>) -> IO(Array<U32> & V.VkResult(Unit)):
  match fuel length:
    case _ W.U64{0,0}: IO.pure(Array<U32> & V.VkResult(Unit),(words,Done{Unit{}}))
    case 0n _: IO.pure(Array<U32> & V.VkResult(Unit),(words,Fail{(1610612741,"Upload chunk count exhausted")}))
    case 1n+rest _:
      +step = W.of_u32(chunk(length))
      do IO<Array<U32> & V.VkResult(Unit)>:
        pair : Array<U32> & V.VkResult(Unit) <- V.Device.write_memory_words(device,memory,destination,source,step,words)
        write_next(pair,array => write(rest,device,memory,W.add(destination,step),W.add(source,step),W.add(length,W.neg(step)),array))

def staged_result(staging: Staging, slice: Slice, end: W.U64, words: Array<U32>, result: V.VkResult(Unit)) -> (Staging & Array<U32>) & V.VkResult(Slice):
  match staging result:
    case Staging{allocation,cursor} Done{unit}: ((Staging{allocation,end},words),Done{slice})
    case _ Fail{error}: ((staging,words),Fail{error})
    case _ _: ((staging,words),Fail{(1610612738,"Invalid staging owner")} )

def staged(staging: Staging, slice: Slice, end: W.U64, pair: Array<U32> & V.VkResult(Unit)) -> (Staging & Array<U32>) & V.VkResult(Slice):
  (words,result) = pair
  staged_result(staging,slice,end,words,result)

def stage_valid(valid: Bool, +device: V.Device, +staging: Staging, +source: W.U64, +length: W.U64, words: Array<U32>) -> IO((Staging & Array<U32>) & V.VkResult(Slice)):
  match valid staging:
    case True{} Staging{Allocation{+buffer,+memory,capacity},+cursor}:
      do IO<(Staging & Array<U32>) & V.VkResult(Slice)>:
        pair : Array<U32> & V.VkResult(Unit) <- write(byte_fuel(length),device,memory,cursor,source,length,words)
        return staged(staging,Slice{buffer,cursor,length},W.add(cursor,length),pair)
    case _ _: IO.pure((Staging & Array<U32>) & V.VkResult(Slice),((staging,words),Fail{(1610612739,"Staging destination range exceeds reserved storage")}))

def stage_source(valid: Bool, device: V.Device, +staging: Staging, source: W.U64, +length: W.U64, words: Array<U32>) -> IO((Staging & Array<U32>) & V.VkResult(Slice)):
  match valid staging:
    case False{} _: IO.pure((Staging & Array<U32>) & V.VkResult(Slice),((staging,words),Fail{(1610612739,"Staging source range exceeds its array")}))
    case True{} Empty{}: stage_valid(False{},device,staging,source,length,words)
    case True{} Staging{Allocation{b,m,capacity},cursor}: stage_valid(Core.subrange_contains(capacity,cursor,length),device,staging,source,length,words)

def stage_array(device: V.Device, staging: Staging, +source: W.U64, +length: W.U64, pair: Array<U32> & U32) -> IO((Staging & Array<U32>) & V.VkResult(Slice)):
  (words,+count) = pair
  stage_source(Core.subrange_contains(W.U64{(count << 2n : U32),(count >> 30n : U32)},source,length),device,staging,source,length,words)

def stage(device: V.Device, staging: Staging, source: W.U64, length: W.U64, words: Array<U32>) -> IO((Staging & Array<U32>) & V.VkResult(Slice)):
  stage_array(device,staging,source,length,Array.size(U32,words))
