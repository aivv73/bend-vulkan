import Base
import ../Vulkan.bend as V
import ../src/core.bend as Core
import ../src/constants.bend as vk
import ../deps/bend-collections/src/math/u64.bend as W

def show_u64(value: W.U64) -> String:
  W.U64{lo,hi} = value
  "lo=" ++ U32.show(lo) ++ " hi=" ++ U32.show(hi)

def print_properties(properties: V.PhysicalDeviceProperties) -> IO(Unit):
  V.PhysicalDeviceProperties{name, api, driver, vendor, device, kind} = properties
  IO.print("Vulkan device: " ++ name)

def print_layers(layers: List<V.LayerProperties>) -> IO(Unit):
  match layers:
    case Nil{}:
      IO.pure(Unit,Unit{})
    case Con{V.LayerProperties{name,spec,implementation,description},rest}:
      do IO<Unit>:
        IO.print("Layer: " ++ name)
        print_layers(rest)

def print_extensions(extensions: List<V.ExtensionProperties>, +prefix: String) -> IO(Unit):
  match extensions:
    case Nil{}:
      IO.pure(Unit,Unit{})
    case Con{V.ExtensionProperties{name,version},rest}:
      do IO<Unit>:
        IO.print(prefix ++ name)
        print_extensions(rest,prefix)

def print_heaps(heaps: List<V.MemoryHeap>) -> IO(Unit):
  match heaps:
    case Nil{}:
      IO.pure(Unit,Unit{})
    case Con{V.MemoryHeap{size,flags},rest}:
      do IO<Unit>:
        IO.print("Memory heap size limbs: " ++ show_u64(size) ++ " flags " ++ U32.show(flags))
        print_heaps(rest)

def print_limits(limits: V.PhysicalDeviceLimits) -> IO(Unit):
  V.PhysicalDeviceLimits{image,width,height,colors,push,attributes,bindings,attribute_offset,stride,allocations,atom,copy,row,granularity} = limits
  do IO<Unit>:
    IO.print("Image/framebuffer limits: " ++ U32.show(image) ++ " " ++ U32.show(width) ++ " " ++ U32.show(height))
    IO.print("Color/push/vertex limits: " ++ U32.show(colors) ++ " " ++ U32.show(push) ++ " " ++ U32.show(attributes) ++ " " ++ U32.show(bindings) ++ " " ++ U32.show(attribute_offset) ++ " " ++ U32.show(stride))
    IO.print("Allocation/atom/copy/row limits: " ++ U32.show(allocations) ++ " " ++ show_u64(atom) ++ " " ++ show_u64(copy) ++ " " ++ show_u64(row))

def print_format(properties: V.FormatProperties) -> IO(Unit):
  V.FormatProperties{linear,optimal,buffer} = properties
  IO.print("RGBA8 format masks: " ++ U32.show(linear) ++ " " ++ U32.show(optimal) ++ " " ++ U32.show(buffer))

def print_devices(devices: List<V.PhysicalDevice>, +instance: V.Instance) -> V.Action(Unit):
  match devices:
    case Nil{}:
      V.Action.pure(Unit, Unit{})
    case Con{+physical, rest}:
      do V.Action<Unit>:
        properties : V.PhysicalDeviceProperties <- V.Instance.get_physical_device_properties(instance, physical)
        V.Action.lift(Unit, print_properties(properties))
        extensions : List<V.ExtensionProperties> <- V.Instance.enumerate_device_extensions(instance,physical,None{})
        V.Action.lift(Unit,print_extensions(extensions,"Device extension: "))
        heaps : List<V.MemoryHeap> <- V.Instance.get_physical_device_memory_heaps(instance,physical)
        V.Action.lift(Unit,print_heaps(heaps))
        limits : V.PhysicalDeviceLimits <- V.Instance.get_physical_device_limits(instance,physical)
        V.Action.lift(Unit,print_limits(limits))
        format : V.FormatProperties <- V.Instance.get_physical_device_format_properties(instance,physical,vk.VK_FORMAT_R8G8B8A8_UNORM())
        V.Action.lift(Unit,print_format(format))
        print_devices(rest, instance)

def discover(+entry: V.Entry) -> IO(V.VkResult(Unit)):
  do V.Action<Unit>:
    version : U32 <- V.Entry.enumerate_instance_version(entry)
    V.Action.lift(Unit, IO.print("Loader API version bits: " ++ U32.show(version)))
    layers : List<V.LayerProperties> <- V.Entry.enumerate_instance_layers(entry)
    V.Action.lift(Unit,print_layers(layers))
    extensions : List<V.ExtensionProperties> <- V.Entry.enumerate_instance_extensions(entry,None{})
    V.Action.lift(Unit,print_extensions(extensions,"Instance extension: "))
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    print_devices(devices, instance)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit, entry => discover(entry))
    V.or_exit(Unit, result)
