import Base
import ../Vulkan.bend as V
import ./voxel/interactive.bend as Interactive
import ./buffer_roundtrip.bend as D

type Options is Data:
  Options{split: Bool, trace: Bool}

def options(args: List<String>, flags: Options) -> Options:
  match args:
    case Nil{}: flags
    case Con{+arg,rest}:
      Options{split,trace} = flags
      options(rest,Options{split || String.eq(arg,"--split"),trace || String.eq(arg,"--trace")})

def run(entry: V.Entry, flags: Options) -> V.Action(Unit):
  Options{split,trace} = flags
  Interactive.run(entry,split,trace)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry,options(args,Options{False{},False{}})))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Interactive shutdown leaked wrapper rows")
    V.or_exit(Unit,checked)
    IO.print("Native interactive shutdown rows=0")
