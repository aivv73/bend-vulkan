import Base
import ../Vulkan.bend as V
import ./native.bend as Native
import ./transfers.bend as Transfer
import ./repeated.bend as Repeated
import ../examples/buffer_roundtrip.bend as Demo

def main() -> IO(Unit):
  do IO<Unit>:
    base : V.VkResult(Unit) <- Native.all_checks()
    V.or_exit(Unit,base)
    transfer : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Transfer.run(entry))
    V.or_exit(Unit,transfer)
    repeated : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Repeated.run(entry))
    V.or_exit(Unit,repeated)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Controlled scope leaked")
    V.or_exit(Unit,checked)
    IO.print("Controlled native probes and real GPU integration passed")
