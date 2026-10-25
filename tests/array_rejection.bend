import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W
import ../examples/buffer_roundtrip.bend as Demo

def result_code(expected: U32, result: V.VkResult(Unit)) -> V.Action(Unit):
  match result:
    case Done{unit}:
      Demo.require(U32.is_eq(expected, 0), "Expected upload error")
    case Fail{(+code, message)}:
      Demo.require(U32.is_eq(expected, code), "Upload error mismatch: " ++ U32.show(code) ++ " " ++ message)

def check_owned(owned: Array<U32> & V.VkResult(Unit), expected: U32) -> V.Action(Unit):
  (words, result) = owned
  do V.Action<Unit>:
    Demo.require(Demo.bytes_equal(Array.to_list(~U32, words), [16909060,134678021,202050057,269422093]), "Returned array changed")
    result_code(expected, result)

def words() -> Array<U32>:
  a = [0 : U32*4n]
  a[0] <- 16909060
  a[1] <- 134678021
  a[2] <- 202050057
  a[3] <- 269422093
  a

def run() -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    owned : Array<U32> & V.VkResult(Unit) <- V.Device.write_memory_words(V.Device{0}, V.DeviceMemory{0}, W.zero(),W.zero(), W.of_u32(7), words())
    check_owned(owned, 1610612737)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- run()
    V.or_exit(Unit, result)
    IO.print("Interpreted array ownership rejection passed")
