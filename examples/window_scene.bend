import Base

# XYZ position + RGB color, six F32 words per vertex.
def vertex(x: F32, y: F32, z: F32, +r: F32, +g: F32, +b: F32) -> List<U32>:
  [F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(r),F32.bits(g),F32.bits(b)]

def vertices() -> List<U32>:
  +lo = F32.neg(1.0)
  front back left right top bottom ground =
    List.concat(&1,U32,[vertex(lo,lo,1.0,0.9,0.3,0.15),vertex(1.0,lo,1.0,0.9,0.3,0.15),vertex(1.0,1.0,1.0,0.9,0.3,0.15),vertex(lo,1.0,1.0,0.9,0.3,0.15)])
    List.concat(&1,U32,[vertex(1.0,lo,lo,0.3,0.5,0.9),vertex(lo,lo,lo,0.3,0.5,0.9),vertex(lo,1.0,lo,0.3,0.5,0.9),vertex(1.0,1.0,lo,0.3,0.5,0.9)])
    List.concat(&1,U32,[vertex(lo,lo,lo,0.5,0.3,0.8),vertex(lo,lo,1.0,0.5,0.3,0.8),vertex(lo,1.0,1.0,0.5,0.3,0.8),vertex(lo,1.0,lo,0.5,0.3,0.8)])
    List.concat(&1,U32,[vertex(1.0,lo,1.0,0.2,0.7,0.65),vertex(1.0,lo,lo,0.2,0.7,0.65),vertex(1.0,1.0,lo,0.2,0.7,0.65),vertex(1.0,1.0,1.0,0.2,0.7,0.65)])
    List.concat(&1,U32,[vertex(lo,1.0,1.0,0.95,0.75,0.25),vertex(1.0,1.0,1.0,0.95,0.75,0.25),vertex(1.0,1.0,lo,0.95,0.75,0.25),vertex(lo,1.0,lo,0.95,0.75,0.25)])
    List.concat(&1,U32,[vertex(lo,lo,lo,0.4,0.4,0.45),vertex(1.0,lo,lo,0.4,0.4,0.45),vertex(1.0,lo,1.0,0.4,0.4,0.45),vertex(lo,lo,1.0,0.4,0.4,0.45)])
    List.concat(&1,U32,[vertex(F32.neg(3.0),F32.neg(1.05),3.0,0.25,0.3,0.38),vertex(3.0,F32.neg(1.05),3.0,0.25,0.3,0.38),vertex(3.0,F32.neg(1.05),F32.neg(3.0),0.25,0.3,0.38),vertex(F32.neg(3.0),F32.neg(1.05),F32.neg(3.0),0.25,0.3,0.38)])
  List.concat(&1,U32,[front,back,left,right,top,bottom,ground])

def quad(+base: U32) -> List<U32>:
  [base,U32.inc(base),(base + 2 : U32),(base + 2 : U32),(base + 3 : U32),base]

def indices() -> List<U32>:
  List.concat(&1,U32,[quad(0),quad(4),quad(8),quad(12),quad(16),quad(20),quad(24)])

type Camera is Data:
  Camera{yaw: F32, pitch: F32, distance: F32}

def initial() -> Camera:
  Camera{0.65,0.45,7.0}

def clamp(+x: F32, +low: F32, +high: F32) -> F32:
  F32.max(low,F32.min(x,high))

def key(+code: U32, camera: Camera) -> Camera:
  match code:
    case 114: initial()
    case _:
      Camera{+yaw,+pitch,+distance} = camera
      Camera{(yaw + Bool.pick(F32,U32.is_eq(code,97),F32.neg(0.12),Bool.pick(F32,U32.is_eq(code,100),0.12,0.0)) : F32),
        clamp((pitch + Bool.pick(F32,U32.is_eq(code,119),0.1,Bool.pick(F32,U32.is_eq(code,115),F32.neg(0.1),0.0)) : F32),0.1,1.4),
        clamp((distance + Bool.pick(F32,U32.is_eq(code,113),F32.neg(0.4),Bool.pick(F32,U32.is_eq(code,101),0.4,0.0)) : F32),4.0,15.0)}

def events(xs: List<Event>, camera: Maybe<Camera>) -> Maybe<Camera>:
  match xs camera:
    case _ None{}: None{}
    case Nil{} Some{c}: Some{c}
    case Con{Close{},rest} _: None{}
    case Con{Key{27,True{}},rest} _: None{}
    case Con{Key{code,True{}},rest} Some{c}: events(rest,Some{key(code,c)})
    case Con{event,rest} Some{c}: events(rest,Some{c})

# Column-major P*V: right-handed orbit camera, Vulkan depth [0,1], Y flipped.
# 60-degree vertical field of view, near=0.1, far=100.
def matrix(camera: Camera, width: U32, height: U32) -> List<U32>:
  Camera{+yaw,+pitch,+distance} = camera
  +sy +cy +sp +cp = F32.sin(yaw) F32.cos(yaw) F32.sin(pitch) F32.cos(pitch)
  +f : F32 = 1.7320508
  +fx : F32 = (f * U32.to_f32(height) / U32.to_f32(width) : F32)
  +a : F32 = (100.0 / 99.9 : F32)
  List.map(~F32,~U32,~F32.bits,[
    (fx * cy : F32),(f * sy * sp : F32),F32.neg((a * sy * cp : F32)),F32.neg((sy * cp : F32)),
    0.0,F32.neg((f * cp : F32)),F32.neg((a * sp : F32)),F32.neg(sp),
    F32.neg((fx * sy : F32)),(f * cy * sp : F32),F32.neg((a * cy * cp : F32)),F32.neg((cy * cp : F32)),
    0.0,0.0,(a * distance - 10.0 / 99.9 : F32),distance])
