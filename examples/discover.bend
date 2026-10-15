import Base
import ../Vulkan.bend as V

def print_properties(properties: V.PhysicalDeviceProperties) -> IO(Unit):
  V.PhysicalDeviceProperties{name, api, driver, vendor, device, kind} = properties
  IO.print("Vulkan device: " ++ name)

def print_devices(devices: List<V.PhysicalDevice>, +instance: V.Instance) -> V.Action(Unit):
  match devices:
    case Nil{}:
      V.Action.pure(Unit, Unit{})
    case Con{physical, rest}:
      do V.Action<Unit>:
        properties : V.PhysicalDeviceProperties <- V.Instance.get_physical_device_properties(instance, physical)
        V.Action.lift(Unit, print_properties(properties))
        print_devices(rest, instance)

def discover(+entry: V.Entry) -> IO(V.VkResult(Unit)):
  do V.Action<Unit>:
    version : U32 <- V.Entry.enumerate_instance_version(entry)
    V.Action.lift(Unit, IO.print("Loader API version bits: " ++ U32.show(version)))
    +instance : V.Instance <- V.Entry.create_instance(entry, V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    print_devices(devices, instance)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit, entry => discover(entry))
    V.or_exit(Unit, result)
