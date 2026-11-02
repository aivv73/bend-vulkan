import Base
import bend-window-capture@0.1.0.2/capture.bend as Capture

# Private capture connection: owns only its X11 connection, never the target.
# Only Capture.Window.capture and close_capture may consume this handle.
# Window.frame keeps Base window ABI and Event constructors in the native build.
def open_capture(id: U32, runtime: Window -> Image -> IO(Window & (Image & List<Event>)), open: String -> U32 -> U32 -> IO(Result<&1,&1,U32 & String,Window>)) -> IO(Result<&1,&1,U32 & String,Window>):
  import "./bridge.c"
  import "./bridge.js"

def close_capture(window: Window) -> IO(Unit):
  import "./bridge.c"
  import "./bridge.js"

def captured(pair: Window & Result<&1,&1,U32 & String,Capture.Capture>) -> IO(Result<&1,&1,U32 & String,Capture.Capture>):
  (window,result) = pair
  do IO<Result<&1,&1,U32 & String,Capture.Capture>>:
    close_capture(window)
    return result

def capture(id: U32) -> IO(Result<&1,&1,U32 & String,Capture.Capture>):
  do IO<Result<&1,&1,U32 & String,Capture.Capture>>:
    window : Window <- IO.try(Window,open_capture(id,Window.frame,Window.open))
    pair : Window & Result<&1,&1,U32 & String,Capture.Capture> <- Capture.Window.capture(window)
    captured(pair)

def start(log: String, validation: Bool) -> IO(Result<&1,&1,U32 & String,U32>):
  import "./bridge.c"
  import "./bridge.js"

def status(pid: U32) -> IO(Result<&1,&1,U32 & String,Maybe<U32>>):
  import "./bridge.c"
  import "./bridge.js"

def find(pid: U32) -> IO(Result<&1,&1,U32 & String,U32>):
  import "./bridge.c"
  import "./bridge.js"

# operation: 0 resize, 1 unmap, 2 map/raise. Restricted to this child's window.
def control(id: U32, operation: U32, width: U32, height: U32) -> IO(Result<&1,&1,U32 & String,Unit>):
  import "./bridge.c"
  import "./bridge.js"
