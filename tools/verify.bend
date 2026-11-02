import Base
import ./verification.bend as Check
import ./check_layers.bend as Layers
import ../examples/verify.bend as Examples

def validated(+name: String, output: Check.Output) -> IO(Unit):
  Check.Output{out,err} = output
  +out : String = out
  +err : String = err
  do IO<Unit>:
    Check.log(name ++ "-validation",Check.Output{out,err})
    Check.assert(Check.clean_diagnostics(out ++ err),"Vulkan validation failed for " ++ name ++ ":\n" ++ out ++ err)

def validation_runs(names: List<String>) -> IO(Unit):
  match names:
    case Nil{}: IO.pure(Unit,Unit{})
    case +name <> rest:
      do IO<Unit>:
        output : Check.Output <- Check.run("env",["VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation","VK_LAYER_ENABLES=VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT","./build/" ++ name],60000)
        validated(name,output)
        validation_runs(rest)

def validation(available: Bool) -> IO(Unit):
  match available:
    case False{}:
      do IO<Unit>:
        IO.print("Khronos validation and synchronization validation: unavailable")
        Check.write("build/validation.txt","Khronos validation and synchronization validation: unavailable\n")
    case True{}:
      do IO<Unit>:
        validation_runs(["buffer-roundtrip","offscreen-roundtrip","indexed-offscreen"])
        Check.write("build/validation.txt","Khronos validation and synchronization validation: available\nReal GPU checks passed with validation and synchronization validation enabled.\n")

def sanitized(names: List<String>) -> IO(Unit):
  match names:
    case Nil{}: IO.pure(Unit,Unit{})
    case +name <> rest:
      do IO<Unit>:
        Check.command("bend",["examples/" ++ name ++ ".bend","-o","build/" ++ name ++ "-sanitized.c"])
        Check.command("clang",["-std=c11","-O1","-g","-fsanitize=address,undefined","-fno-omit-frame-pointer","build/" ++ name ++ "-sanitized.c","-lpthread","-lm","-ldl","-o","build/" ++ name ++ "-sanitized"])
        output : Check.Output <- Check.run("env",["ASAN_OPTIONS=detect_leaks=0","UBSAN_OPTIONS=halt_on_error=1","./build/" ++ name ++ "-sanitized"],60000)
        Check.print_output(output)
        sanitized(rest)

def option(valid: Bool) -> IO(Bool):
  match valid:
    case True{}: IO.pure(Bool,True{})
    case False{}: IO.die(Bool,1,"Usage: bend tools/verify.bend [--sanitize]")

def options(args: List<String>) -> IO(Bool):
  match args:
    case Nil{}: IO.pure(Bool,False{})
    case flag <> Nil{}:
      option(String.eq(flag,"--sanitize"))
    case _: IO.die(Bool,1,"Usage: bend tools/verify.bend [--sanitize]")

def sanitize(enabled: Bool) -> IO(Unit):
  match enabled:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: sanitized(["buffer_roundtrip","offscreen_roundtrip","indexed_offscreen"])

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    enabled : Bool <- options(List.drop(&1,String,args,1n))
    Check.setup()
    Check.command("python3",["tools/generate.py","--check"])
    Layers.check()
    Check.command("python3",["tools/build_shaders.py","--check"])
    Check.command("bend",["PROOF.bend"])
    Check.command("bend",["tools/window_verification/PROOF.bend","--verdict"])
    Examples.verify()
    discovery : String <- Check.read("build/discovery.txt")
    validation(String.contains(discovery,"Layer: VK_LAYER_KHRONOS_validation\n"))
    sanitize(enabled)
    IO.print("Generation, proofs, and real Vulkan example validation passed.")
