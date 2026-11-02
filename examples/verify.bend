import Base
import ../tools/verification.bend as Check

def linkage(name: String, output: Check.Output) -> IO(Unit):
  Check.Output{out,err} = output
  +out : String = out
  Check.assert(Bool.not(String.contains(out,"libX11") || String.contains(out,"libxcb")),"Headless example gained a display dependency: " ++ name)

def discovery(is_discovery: Bool, out: String) -> IO(Unit):
  match is_discovery:
    case True{}: Check.write("build/discovery.txt",out)
    case False{}: IO.pure(Unit,Unit{})

def inspect(+name: String, marker: String, output: Check.Output) -> IO(Unit):
  Check.Output{out,err} = output
  +out : String = out
  +err : String = err
  do IO<Unit>:
    Check.log(name,Check.Output{out,err})
    Check.assert(String.contains(out,marker),name ++ " omitted its success marker")
    linked : Check.Output <- Check.run("ldd",["build/" ++ name],10000)
    linkage(name,linked)
    discovery(String.eq(name,"discover"),out)

def examples(items: List<(String & (String & String))>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit,Unit{})
    case (source,(+name,marker)) <> rest:
      do IO<Unit>:
        Check.command("bend",["examples/" ++ source ++ ".bend","-o","build/" ++ name])
        output : Check.Output <- Check.run("./build/" ++ name,[],60000)
        inspect(name,marker,output)
        examples(rest)

def verify() -> IO(Unit):
  do IO<Unit>:
    Check.command("bend",["examples/PROOF.bend"])
    examples([("discover",("discover","Loader API version bits:")),
      ("indexed_offscreen",("indexed-offscreen","Indexed RGBA8+D32 every-pixel occlusion")),
      ("offscreen_roundtrip",("offscreen-roundtrip","Optimal RGBA8 image clear")),
      ("buffer_roundtrip",("buffer-roundtrip","Host roundtrip and GPU buffer fill verified"))])
    IO.print("General Vulkan examples passed.")

def main() -> IO(Unit):
  do IO<Unit>:
    Check.setup()
    verify()
