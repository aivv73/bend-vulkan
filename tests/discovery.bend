import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo
import ./native.bend as T

def check_heaps(heaps: List<V.MemoryHeap>) -> V.Action(Unit):
  match heaps:
    case Nil{}:
      IO.pure(V.VkResult(Unit),Fail{(1,"No memory heaps")})
    case Con{V.MemoryHeap{size,flags},rest}:
      Demo.require(Bool.not(W.is_zero(size)),"Zero memory heap size")

def check_limits(limits: V.PhysicalDeviceLimits) -> V.Action(Unit):
  V.PhysicalDeviceLimits{image,width,height,colors,push,attributes,bindings,offset,stride,allocations,atom,copy,row,granularity} = limits
  Demo.require(Bool.and(Bool.and(U32.is_ne(image,0),U32.is_ne(allocations,0)),Bool.and(Bool.not(W.is_zero(atom)),Bool.and(Bool.not(W.is_zero(copy)),Bool.not(W.is_zero(row))))),"Invalid physical limits")

def query_layers(layers: List<V.LayerProperties>, +entry: V.Entry, +instance: V.Instance, +physical: V.PhysicalDevice) -> V.Action(Unit):
  match layers:
    case Nil{}:
      V.Action.pure(Unit,Unit{})
    case Con{V.LayerProperties{+name,spec,implementation,description},rest}:
      do V.Action<Unit>:
        instance_extensions : List<V.ExtensionProperties> <- V.Entry.enumerate_instance_extensions(entry,Some{name})
        device_extensions : List<V.ExtensionProperties> <- V.Instance.enumerate_device_extensions(instance,physical,Some{name})
        return Unit{}

def optional_device_layer_result(result: V.VkResult(List<V.ExtensionProperties>)) -> V.Action(Unit):
  match result:
    case Done{extensions}:
      V.Action.pure(Unit,Unit{})
    case Fail{(code,message)}:
      Demo.require(U32.is_eq(code,4294967290),"Unexpected device layer query error")

def optional_device_layer(instance: V.Instance, physical: V.PhysicalDevice) -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    result : V.VkResult(List<V.ExtensionProperties>) <- V.Instance.enumerate_device_extensions(instance,physical,Some{"VK_BEND_missing_layer"})
    optional_device_layer_result(result)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    layers : List<V.LayerProperties> <- V.Entry.enumerate_instance_layers(entry)
    extensions : List<V.ExtensionProperties> <- V.Entry.enumerate_instance_extensions(entry,None{})
    T.expect_error(List<V.LayerProperties>,1610612738,V.Entry.enumerate_instance_layers(V.Entry{0}))
    T.expect_error(List<V.ExtensionProperties>,4294967290,V.Entry.enumerate_instance_extensions(entry,Some{"VK_BEND_missing_layer"}))
    T.expect_error(List<V.ExtensionProperties>,1610612739,V.Entry.enumerate_instance_extensions(entry,Some{SCon{Chr{0},SNil{}}}))
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- Demo.first(devices)
    query_layers(layers,entry,instance,physical)
    device_extensions : List<V.ExtensionProperties> <- V.Instance.enumerate_device_extensions(instance,physical,None{})
    optional_device_layer(instance,physical)
    T.expect_error(List<V.ExtensionProperties>,1610612739,V.Instance.enumerate_device_extensions(instance,physical,Some{SCon{Chr{0},SNil{}}}))
    heaps : List<V.MemoryHeap> <- V.Instance.get_physical_device_memory_heaps(instance,physical)
    check_heaps(heaps)
    limits : V.PhysicalDeviceLimits <- V.Instance.get_physical_device_limits(instance,physical)
    check_limits(limits)
    format : V.FormatProperties <- V.Instance.get_physical_device_format_properties(instance,physical,vk.VK_FORMAT_R8G8B8A8_UNORM())
    T.expect_error(V.FormatProperties,1610612739,V.Instance.get_physical_device_format_properties(instance,physical,185))
    T.expect_error(V.FormatProperties,1610612739,V.Instance.get_physical_device_format_properties(instance,physical,4294967295))
    T.expect_error(V.PhysicalDeviceLimits,1610612738,V.Instance.get_physical_device_limits(instance,V.PhysicalDevice{0}))
    T.expect_error(List<V.MemoryHeap>,1610612738,V.Instance.get_physical_device_memory_heaps(V.Instance{0},physical))
    T.expect_error(List<V.ExtensionProperties>,1610612738,V.Instance.enumerate_device_extensions(V.Instance{0},physical,None{}))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    IO.print("Capability discovery and raw limb adapters passed")
