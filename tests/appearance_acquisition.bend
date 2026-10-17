import Base
import ../Vulkan.bend as V
import ../deps/bend-collections/src/math/u64.bend as W
import ../deps/bend-voxel/render.bend as R
import ../deps/bend-voxel/voxel.bend as X
import ../deps/bend-voxel/main.bend as Controls
import ../examples/window.bend as WSI
import ../examples/buffer_roundtrip.bend as D
import ../examples/indexed_offscreen.bend as E
import ../examples/voxel/interactive.bend as I
import ../examples/voxel/scene.bend as Scene
import ../examples/voxel/appearance.bend as A
import ../examples/voxel/presentation.bend as P
import ../examples/voxel/mesh.bend as M
import ../examples/voxel/viewport.bend as View
import ../examples/voxel/renderer.bend as GPU


type RecordedState is Data:
  RecordedState{camera: R.Camera, controls: Controls.Controls, pointer: I.Pointer}

def geometry_bytes(+device: V.Device, geometry: GPU.Geometry) -> V.Action(List<U32>):
  match geometry:
    case GPU.Empty{}: V.Action.pure(List<U32>,[])
    case GPU.Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},+count}:
      do V.Action<List<U32>>:
        vertices : List<U32> <- V.Device.read_memory(device,vm,W.zero(),(count / 6 * 160 : U32))
        indices : List<U32> <- V.Device.read_memory(device,im,W.zero(),(count * 4 : U32))
        return List.append(&1,U32,vertices,indices)

def encoded_bytes(result: Maybe<Array<U32>>) -> List<U32>:
  match result:
    case None{}: []
    case Some{words}: E.bytes(List.take(&1,U32,Array.to_list(~U32,words),584n))

def uniform_memory(assets: Scene.Assets) -> V.DeviceMemory:
  Scene.Assets{E.BoundBuffer{ub,um},s,ss,p,f,sd,sampler,shadow,sp,sf,ps,fl,ml,indices,palette} = assets
  um

def checked(+context: WSI.Context, app: I.Session, recorded: RecordedState) -> V.Action(Unit):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  I.Session{I.World{body,M.Mesh{+faces,+size,+bounds,vs,ix},+camera,+controls,+revision,original,+point,dirty},target,phase,+width,+height,mapped,recreate,frames,generations,Scene.Group{+assets,+geometry,+installed,+uploads}} = app
  RecordedState{+frame_camera,+frame_controls,+frame_point} = recorded
  +vw = (GPU.vertex_length(size) / 4 : U32)
  +iw = (GPU.index_length(size) / 4 : U32)
  um = uniform_memory(assets)
  +expected : A.FrameInput = A.FrameInput{R.Camera.basis(frame_camera),width,height,I.frame_extent(bounds),Scene.palette(assets),I.hover(View.Mapping{width,height,width,height},frame_camera,frame_controls,frame_point,faces),A.Unorm{},A.Shaded{}}
  do V.Action<Unit>:
    D.require(U32.is_eq(revision,1) && U32.is_eq(installed,1) && U32.is_eq(uploads,4),"Acquisition event must install revision one after the old revision zero")
    D.require(Bool.not(R.Camera.equal(camera,R.Camera.atelier())),"Acquisition-time camera event must change the stored camera")
    D.require(dirty && Bool.not(R.Camera.equal(camera,frame_camera)),"Submitted pointer and Presenting camera events must remain dirty after completion and command reset")
    actual : List<U32> <- geometry_bytes(device,geometry)
    D.require(D.bytes_equal(actual,List.append(&1,U32,E.bytes(List.take(&1,U32,Array.to_list(~U32,vs),U32.to_nat(vw))),E.bytes(List.take(&1,U32,Array.to_list(~U32,ix),U32.to_nat(iw))))),"Actual installed vertex and index device bytes must match latest CPU exterior")
    uniform : List<U32> <- V.Device.read_memory(device,um,W.zero(),2336)
    D.require(D.bytes_equal(uniform,encoded_bytes(A.encode(expected))),"Actual uniform memory must match latest mesh hover, selection and camera")
    V.Action.lift(Unit,IO.print("Actual acquisition-time edit/camera/hover installed revision=1 uploads=4 and matched device geometry plus all 2336 frame bytes"))

def finish(fuel: Nat, +context: WSI.Context, +frame: P.Frame, app: I.Session, +recorded: RecordedState, +present_event: Bool) -> V.Action(Unit):
  match fuel app:
    case 0n _: D.require(False{},"Native acquisition frame did not complete")
    case 1n+rest I.Session{world,target,P.Idle{},width,height,mapped,recreate,frames,generations,scene}:
      checked(context,I.Session{world,target,P.Idle{},width,height,mapped,recreate,frames,generations,scene},recorded)
    case 1n+rest I.Session{world,target,P.Presenting{replace,lost},+width,+height,+mapped,recreate,+frames,+generations,+scene}:
      do V.Action<Unit>:
        changed : I.World <- I.diagnostics(True{},scene,I.fly(world,Bool.pick(Nat,present_event,0n,16n)),width,height,mapped,False{},frames,generations)
        next : I.Session <- I.advance(frame,I.Session{changed,target,P.Presenting{replace,lost},width,height,mapped,recreate,frames,generations,scene},context)
        finish(rest,context,frame,next,recorded,True{})
    case 1n+rest app:
      do V.Action<Unit>:
        next : I.Session <- I.advance(frame,app,context)
        finish(rest,context,frame,next,recorded,present_event)

def submitted(+context: WSI.Context, +frame: P.Frame, app: I.Session) -> V.Action(Unit):
  match app:
    case I.Session{I.World{body,mesh,+camera,+controls,revision,original,+point,dirty},target,P.Submitted{index,replace},+width,+height,+mapped,recreate,+frames,+generations,+scene}:
      do V.Action<Unit>:
        moved : I.World <- I.diagnostics(True{},scene,I.pointer(I.World{body,mesh,camera,controls,revision,original,point,dirty},290,208),width,height,mapped,False{},frames,generations)
        finish(100n,context,frame,I.Session{moved,target,P.Submitted{index,replace},width,height,mapped,recreate,frames,generations,scene},RecordedState{camera,controls,point},False{})
    case _: D.require(False{},"Acquisition fixture must submit before queued pointer/camera events")

def modified(+context: WSI.Context, +frame: P.Frame, +target: P.Target, +scene: Scene.Group, edited: Maybe<I.World>, +index: U32) -> V.Action(Unit):
  match edited:
    case None{}: D.require(False{},"Acquisition fixture unexpectedly closed")
    case Some{world}:
      do V.Action<Unit>:
        next : I.Session <- I.advance(frame,I.Session{I.fly(I.key(world,119,True{}),16n),Some{target},P.Acquiring{index,False{}},640,480,True{},False{},0,1,scene},context)
        submitted(context,frame,next)

def acquired(+context: WSI.Context, +frame: P.Frame, +target: P.Target, +scene: Scene.Group, world: I.World, outcome: V.AcquireOutcome) -> V.Action(Unit):
  match outcome:
    case V.Acquired{+index,suboptimal}:
      do V.Action<Unit>:
        edited : Maybe<I.World> <- I.events([Move{292,210},Mouse{292,210,0,True{}},Move{291,209}],world,View.Mapping{640,480,640,480})
        modified(context,frame,target,scene,edited,index)
    case _: D.require(False{},"Controlled native acquisition did not return an image")

def installed(+context: WSI.Context, +frame: P.Frame, +target: P.Target, body: X.Body, camera: R.Camera, controls: Controls.Controls, original: I.Original, point: I.Pointer, pair: Scene.Group & M.Mesh) -> V.Action(Unit):
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  P.Frame{pool,command,+acquire,render,present,finished} = frame
  (+scene,mesh) = pair
  do V.Action<Unit>:
    outcome : V.AcquireOutcome <- V.Device.acquire(device,I.target_swapchain(target),acquire,W.of_u32(1000000000))
    acquired(context,frame,target,scene,I.World{body,mesh,camera,controls,0,original,point,True{}},outcome)

def initial(+context: WSI.Context, +frame: P.Frame, +target: P.Target, scene: Scene.Group, world: I.World) -> V.Action(Unit):
  WSI.Context{window,+instance,+physical,surface,+device,g,p} = context
  I.World{body,mesh,camera,controls,revision,original,point,dirty} = world
  do V.Action<Unit>:
    pair : Scene.Group & M.Mesh <- Scene.install(instance,physical,device,scene,0,mesh)
    installed(context,frame,target,body,camera,controls,original,point,pair)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend acquisition consistency",False{})
    +frame : P.Frame <- P.frame(I.device(context))
    +scene : Scene.Group <- I.scene_create(context)
    raw : P.Target <- P.build(context,640,480)
    +target : P.Target <- P.promote(I.device(context),raw,Scene.assets(scene))
    world : I.World <- I.initial_scene(I.Atelier{})
    initial(context,frame,target,scene,world)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Acquisition fixture leaked rows")
    V.or_exit(Unit,checked)
