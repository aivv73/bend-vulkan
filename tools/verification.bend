import Base

type Output is Data:
  Output{out: String, err: String}

def assert(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def write_done(pair: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,result) = pair
  do IO<Unit>:
    File.close(file)
    IO.pass(Unit,result)

def write(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    pair : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,text)
    write_done(pair)

def read_done(pair: File & Result<&1,&1,U32 & String,String>) -> IO(String):
  (file,result) = pair
  do IO<String>:
    File.close(file)
    IO.pass(String,result)

def read(path: String) -> IO(String):
  do IO<String>:
    file : File <- IO.try(File,File.open(path,"r"))
    pair : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
    read_done(pair)

def completed(label: String, value: U32 & (String & String)) -> IO(Output):
  (status,pair) = value
  (out,err) = pair
  +out : String = out
  +err : String = err
  do IO<Output>:
    assert(U32.is_zero(status),label ++ " failed:\n" ++ out ++ err)
    return Output{out,err}

def run(+program: String, args: List<String>, timeout: U32) -> IO(Output):
  do IO<Output>:
    IO.print("+ " ++ program)
    result : U32 & (String & String) <- IO.try(U32 & (String & String),Process.run(program,args,"",16777216,timeout))
    completed(program,result)

def print_output(output: Output) -> IO(Unit):
  Output{out,err} = output
  do IO<Unit>:
    IO.write(out)
    IO.write(err)

def command(program: String, args: List<String>) -> IO(Unit):
  do IO<Unit>:
    output : Output <- run(program,args,300000)
    print_output(output)

def check_version(output: Output) -> IO(Unit):
  Output{+out,err} = output
  assert(String.eq(String.trim(out),"bend 2.0.39"),"Native effects require bend 2.0.39; found " ++ out)

def setup() -> IO(Unit):
  do IO<Unit>:
    version : Output <- run("bend",["version"],10000)
    check_version(version)
    command("mkdir",["-p","build"])

def clean_diagnostics(+text: String) -> Bool:
  Bool.not(String.contains(text,"Validation Error") || String.contains(text,"SYNC-HAZARD") || String.contains(text,"VUID-"))

def log(+name: String, output: Output) -> IO(Unit):
  Output{out,err} = output
  +out : String = out
  do IO<Unit>:
    write("build/" ++ name ++ ".log",out ++ err)
    IO.write(out)
