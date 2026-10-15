import Base
import ../Vulkan.bend as V
import ./native.bend as Native
import ./discovery.bend as Discovery
import ./transfers.bend as Transfer
import ./repeated.bend as Repeated
import ./images.bend as Images
import ./offscreen.bend as Offscreen
import ./rendering.bend as Rendering
import ./graphics_resources.bend as Graphics
import ../examples/indexed_offscreen.bend as Indexed
import ./image_repeated.bend as ImageRepeated
import ./image_formats.bend as ImageFormats
import ../examples/buffer_roundtrip.bend as Demo

def main() -> IO(Unit):
  do IO<Unit>:
    discovery : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Discovery.run(entry))
    V.or_exit(Unit,discovery)
    base : V.VkResult(Unit) <- Native.all_checks()
    V.or_exit(Unit,base)
    transfer : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Transfer.run(entry))
    V.or_exit(Unit,transfer)
    repeated : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Repeated.run(entry))
    V.or_exit(Unit,repeated)
    images : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Images.run(entry))
    V.or_exit(Unit,images)
    offscreen : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Offscreen.run(entry))
    V.or_exit(Unit,offscreen)
    rendering : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Rendering.run(entry))
    V.or_exit(Unit,rendering)
    image_repeated : V.VkResult(Unit) <- V.Entry.with(Unit,entry => ImageRepeated.run(entry))
    V.or_exit(Unit,image_repeated)
    image_formats : V.VkResult(Unit) <- V.Entry.with(Unit,entry => ImageFormats.run(entry))
    V.or_exit(Unit,image_formats)
    graphics : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Graphics.run(entry))
    V.or_exit(Unit,graphics)
    indexed : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Indexed.run(entry))
    V.or_exit(Unit,indexed)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- Demo.require(U32.is_eq(count,0),"Controlled scope leaked")
    V.or_exit(Unit,checked)
    IO.print("Controlled native probes and real GPU integration passed")
