import Base
import ../Vulkan.bend as V
import ./voxel/interactive.bend as Interactive
import ./buffer_roundtrip.bend as D

type Options is Data:
  Options{split: Bool, trace: Bool, cube: Bool}

def options(args: List<String>, flags: Options) -> Options:
  match args:
    case Nil{}: flags
    case Con{+arg,rest}:
      Options{split,trace,cube} = flags
      options(rest,Options{split || String.eq(arg,"--split"),trace || String.eq(arg,"--trace"),cube || String.eq(arg,"--cube")})

def run(entry: V.Entry, flags: Options) -> V.Action(Unit):
  Options{split,trace,cube} = flags
  Interactive.run(entry,split,trace,Bool.pick(Interactive.Original,cube,Interactive.Cube{},Interactive.Atelier{}))

def shutdown(trace: Bool) -> IO(Unit):
  match trace:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: IO.print("Native interactive shutdown rows=0")

def traced(flags: Options) -> Bool:
  Options{s,t,c} = flags
  t

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +flags : Options = options(args,Options{False{},False{},False{}})
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry,flags))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Interactive shutdown leaked wrapper rows")
    V.or_exit(Unit,checked)
    shutdown(traced(flags))
