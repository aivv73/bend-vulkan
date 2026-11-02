import Base
import ./verification.bend as Check

def unquote(text: String) -> String:
  match text:
    case SCon{'"',rest}: rest
    case SCon{'\'',rest}: rest
    case other: other

def token(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{' ',rest}: ""
    case SCon{'\t',rest}: ""
    case SCon{'"',rest}: ""
    case SCon{'\'',rest}: ""
    case SCon{head,rest}: SCon{head,token(rest)}

def target_ok(library: Bool, +target: String) -> Bool:
  Bool.not(String.starts_with(target,"../") || String.starts_with(target,"consumers/") || String.starts_with(target,"deps/bend-voxel/") || (library && (String.starts_with(target,"examples/") || String.starts_with(target,"shaders/"))))

def checked_target(+source: String, library: Bool, output: Check.Output) -> IO(Unit):
  Check.Output{out,err} = output
  +target : String = String.trim(out)
  do IO<Unit>:
    Check.assert(target_ok(library,target),source ++ " has a forbidden import: " ++ target)
    Check.command("test",["-f",target])

def relative_import(relative: Bool, +source: String, directory: String, library: Bool, name: String) -> IO(Unit):
  match relative:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      do IO<Unit>:
        output : Check.Output <- Check.run("realpath",["-e","--relative-to=.",directory ++ "/" ++ name],10000)
        checked_target(source,library,output)

def import_line(is_import: Bool, source: String, directory: String, library: Bool, line: String) -> IO(Unit):
  match is_import:
    case False{}: IO.pure(Unit,Unit{})
    case True{}:
      +name : String = token(unquote(String.trim_start(String.drop(line,7n))))
      relative_import(String.starts_with(name,"."),source,directory,library,name)

def lines(xs: List<&2,String>, +source: String, +directory: String, +library: Bool) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      +line : String = String.trim_start(line)
      do IO<Unit>:
        import_line(String.starts_with(line,"import "),source,directory,library,line)
        lines(rest,source,directory,library)

def source_file(+source: String, output: Check.Output) -> IO(Unit):
  Check.Output{directory,err} = output
  +library : Bool = Bool.not(String.starts_with(source,"examples/") || String.starts_with(source,"shaders/"))
  do IO<Unit>:
    text : String <- Check.read(source)
    lines(String.lines(text),source,String.trim(directory),library)

def files(xs: List<&2,String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: files(rest)
    case +source <> rest:
      do IO<Unit>:
        directory : Check.Output <- Check.run("dirname",[source],10000)
        source_file(source,directory)
        files(rest)

def found(output: Check.Output) -> IO(Unit):
  Check.Output{out,err} = output
  files(String.lines(out))

def check() -> IO(Unit):
  do IO<Unit>:
    output : Check.Output <- Check.run("find",["Vulkan.bend","LAWS.bend","PROOF.bend","src","examples","shaders","-name","*.bend","-type","f"],10000)
    found(output)
    IO.print("Vulkan API and general examples have no consumer imports.")

def main() -> IO(Unit):
  check()
