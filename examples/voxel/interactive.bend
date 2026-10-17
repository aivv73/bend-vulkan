import Base
import ../../Vulkan.bend as V
import ../../src/core.bend as Core
import ../../deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-voxel/main.bend as Controls
import ../../deps/bend-voxel/render.bend as R
import ../../deps/bend-voxel/voxel.bend as X
import ../window.bend as WSI
import ../buffer_roundtrip.bend as D
import ./mesh.bend as M
import ./renderer.bend as GPU
import ./presentation.bend as P
import ./viewport.bend as View

type World is Type:
  World{body: X.Body, mesh: M.Mesh, camera: R.Camera, controls: Controls.Controls, revision: U32, uploaded: U32, geometry: GPU.Geometry, uploads: U32, changed: Bool}
type Session is Type:
  Session{world: World, target: Maybe<&2,P.Target>, phase: P.Phase, width: U32, height: U32, mapped: Bool, recreate: Bool, frames: U32, generations: U32}

def initial(result: X.Body & M.Mesh) -> World:
  (body,mesh) = result
  World{body,mesh,R.Camera.initial(),Controls.Controls.initial(),0,4294967295,GPU.Empty{},0,True{}}

def edited(result: X.Body & M.Mesh, camera: R.Camera, controls: Controls.Controls, revision: U32, uploaded: U32, geometry: GPU.Geometry, uploads: U32) -> World:
  (body,mesh) = result
  World{body,mesh,camera,controls,U32.inc(revision),uploaded,geometry,uploads,True{}}

def changed(world: World, sphere: X.MetricSphere) -> World:
  World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old} = world
  edited(M.build(X.Body.cut(body,sphere)),camera,controls,revision,uploaded,geometry,uploads)

def picked(world: World, hit: Maybe<&2,X.MetricSphere>) -> World:
  match hit:
    case None{}: world
    case Some{sphere}: changed(world,sphere)

def click(world: World, +view: View.Viewport, +x: U32, +y: U32) -> World:
  World{body,mesh,+camera,+controls,revision,uploaded,geometry,uploads,old} = world
  M.Mesh{+faces,count,vs,ix} = mesh
  View.Viewport{+width,+height} = view
  picked(World{body,M.Mesh{faces,count,vs,ix},camera,controls,revision,uploaded,geometry,uploads,old},View.target(view,camera,faces,Bool.pick(U32,Controls.Controls.capture(controls),(width / 2 : U32),x),Bool.pick(U32,Controls.Controls.capture(controls),(height / 2 : U32),y)))

def reset(world: World) -> World:
  World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old} = world
  edited(M.build(X.Body.solid(3n)),camera,controls,revision,uploaded,geometry,uploads)

def key(world: World, code: U32, down: Bool) -> World:
  World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old} = world
  World{body,mesh,camera,Controls.Controls.key(code,down,controls),revision,uploaded,geometry,uploads,old}

def capture(world: World, looking: Bool) -> World:
  World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old} = world
  World{body,mesh,camera,Controls.Controls.look(controls,looking),revision,uploaded,geometry,uploads,old}

def look_active(active: Bool, world: World, dx: F32, dy: F32) -> World:
  match active world:
    case False{} _: world
    case True{} World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old}:
      World{body,mesh,R.Camera.look(camera,dx,dy),controls,revision,uploaded,geometry,uploads,True{}}

def look(world: World, dx: F32, dy: F32) -> World:
  World{body,mesh,camera,+controls,revision,uploaded,geometry,uploads,old} = world
  look_active(Controls.Controls.capture(controls),World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,old},dx,dy)

def click_point(world: World, view: View.Viewport, point: U32 & U32) -> World:
  (x,y) = point
  click(world,view,x,y)

def mapped_click(world: World, +mapping: View.Mapping, x: U32, y: U32) -> World:
  View.Mapping{ww,wh,width,height} = mapping
  click_point(world,View.Viewport{width,height},View.map_point(mapping,x,y))

def event(event: Event, world: World, view: View.Mapping) -> Maybe<World>:
  match event:
    case Close{}: None{}
    case Key{27,True{}}: None{}
    case Key{32,True{}}: Some{changed(world,X.MetricSphere.brush(X.PointCm.cell(X.Cell{6,6,6})))}
    case Key{114,True{}}: Some{reset(world)}
    case Key{82,True{}}: Some{reset(world)}
    case Key{code,down}: Some{key(world,code,down)}
    case Mouse{x,y,1,down}: Some{capture(world,down)}
    case Mouse{x,y,0,True{}}: Some{mapped_click(world,view,x,y)}
    case Look{dx,dy}: Some{look(world,dx,dy)}
    case _: Some{world}

def events(xs: List<Event>, world: World, +view: View.Mapping) -> Maybe<World>:
  match xs:
    case Nil{}: Some{world}
    case Con{head,rest}: Maybe.bind(&1,World,World,event(head,world,view),next => events(rest,next,view))

def fly(world: World, +elapsed: Nat) -> World:
  World{body,mesh,+camera,+controls,revision,uploaded,geometry,uploads,old} = world
  +next = Controls.Controls.fly(controls,camera,elapsed)
  World{body,mesh,next,controls,revision,uploaded,geometry,uploads,old || Bool.not(R.Camera.equal(camera,next))}

def uploaded(result: GPU.Geometry & M.Mesh, body: X.Body, camera: R.Camera, controls: Controls.Controls, +revision: U32, uploads: U32, changed: Bool) -> World:
  (geometry,M.Mesh{faces,+count,vs,ix}) = result
  World{body,M.Mesh{faces,count,vs,ix},camera,controls,revision,revision,geometry,(uploads + Bool.pick(U32,U32.is_zero(count),0,2) : U32),changed}

def rebuild_needed(needed: Bool, world: World, context: WSI.Context) -> V.Action(World):
  match needed world:
    case False{} _: V.Action.pure(World,world)
    case True{} World{body,mesh,camera,controls,+revision,previous,geometry,uploads,changed}:
      WSI.Context{window,instance,physical,surface,device,g,p} = context
      do V.Action<World>:
        installed : GPU.Geometry & M.Mesh <- GPU.upload_mesh(instance,physical,device,geometry,mesh)
        return uploaded(installed,body,camera,controls,revision,uploads,changed)
def rebuild(world: World, +context: WSI.Context) -> V.Action(World):
  match world:
    case World{body,mesh,camera,controls,+revision,+previous,geometry,uploads,changed}:
      rebuild_needed(U32.is_ne(revision,previous),World{body,mesh,camera,controls,revision,previous,geometry,uploads,changed},context)


def capture_granted(world: World, looking: Bool, actual: Bool) -> World:
  match looking actual:
    case True{} False{}: capture(world,False{})
    case _ _: world

def capture_requested(window: V.NativeWindow, world: World, request: Maybe<&2,Bool>) -> V.Action(World):
  match request:
    case None{}: V.Action.pure(World,world)
    case Some{+looking}:
      do V.Action<World>:
        actual : Bool <- V.NativeWindow.capture(window,looking)
        return capture_granted(world,looking,actual)

def capture_result(window: V.NativeWindow, world: World, result: Controls.Controls & Maybe<&2,Bool>) -> V.Action(World):
  World{body,mesh,camera,old,revision,uploaded,geometry,uploads,changed} = world
  (controls,request) = result
  capture_requested(window,World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,changed},request)

def capture_apply(window: V.NativeWindow, world: World) -> V.Action(World):
  World{body,mesh,camera,+controls,revision,uploaded,geometry,uploads,changed} = world
  capture_result(window,World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,changed},Controls.Controls.request(controls))

def target_destroy(device: V.Device, target: Maybe<&2,P.Target>) -> V.Action(Unit):
  match target:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{target}: P.destroy(device,target)

def target_swapchain(target: P.Target) -> V.Swapchain:
  P.Target{swapchain,images,depth,pass,layout,pipeline,width,height} = target
  swapchain

def idle_target(+context: WSI.Context, frame: P.Frame, world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, frames: U32, +generations: U32, replace: Bool) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  match replace:
    case True{}:
      do V.Action<Session>:
        target_destroy(device,target)
        +next : P.Target <- P.build(context,width,height)
        return Session{world,Some{next},P.Idle{},width,height,mapped,False{},frames,U32.inc(generations)}
    case False{}: V.Action.pure(Session,Session{world,target,P.Idle{},width,height,mapped,False{},frames,generations})

def acquire_result(world: World, +target: P.Target, +width: U32, +height: U32, +mapped: Bool, frames: U32, generations: U32, outcome: V.AcquireOutcome) -> V.Action(Session):
  match outcome:
    case V.Acquired{index,suboptimal}: V.Action.pure(Session,Session{world,Some{target},P.Acquiring{index,suboptimal},width,height,mapped,False{},frames,generations})
    case V.AcquireOutOfDate{}: V.Action.pure(Session,Session{world,Some{target},P.Idle{},width,height,mapped,True{},frames,generations})
    case V.AcquireSurfaceLost{}: IO.pure(V.VkResult(Session),Fail{(3294967296,"Surface lost during acquisition")})
    case _: V.Action.pure(Session,Session{world,Some{target},P.Idle{},width,height,mapped,False{},frames,generations})

def begin_ready(context: WSI.Context, frame: P.Frame, world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, frames: U32, generations: U32) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  match target:
    case None{}: V.Action.pure(Session,Session{world,None{},P.Idle{},width,height,mapped,True{},frames,generations})
    case Some{+target}:
      do V.Action<Session>:
        outcome : V.AcquireOutcome <- V.Device.acquire(device,target_swapchain(target),acquire,W.of_u32(1000000))
        acquire_result(world,target,width,height,mapped,frames,generations,outcome)

def idle_prepared(app: Session, context: WSI.Context, frame: P.Frame) -> V.Action(Session):
  Session{world,target,phase,width,height,mapped,recreate,frames,generations} = app
  begin_ready(context,frame,world,target,width,height,mapped,frames,generations)

def idle(world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, replace: Bool, frames: U32, generations: U32, +context: WSI.Context, +frame: P.Frame, drawable: Bool) -> V.Action(Session):
  match drawable:
    case False{}: V.Action.pure(Session,Session{world,target,P.Idle{},width,height,mapped,replace,frames,generations})
    case True{}:
      do V.Action<Session>:
        next : World <- rebuild(world,context)
        app : Session <- idle_target(context,frame,next,target,width,height,mapped,frames,generations,replace)
        idle_prepared(app,context,frame)

def acquired_ready(+context: WSI.Context, +frame: P.Frame, app: Session, +index: U32, suboptimal: Bool, status: U32) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{World{body,mesh,+camera,controls,revision,uploaded,+geometry,uploads,changed},target,phase,width,height,mapped,replace,frames,generations} = app
  match target status:
    case Some{+target} 0:
      do V.Action<Session>:
        V.Fence.reset(acquire)
        P.record(device,frame,target,index,camera,geometry)
        return Session{World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,changed},Some{target},P.Submitted{index,suboptimal},width,height,mapped,replace,frames,generations}
    case _ _:
      V.Action.pure(Session,Session{World{body,mesh,camera,controls,revision,uploaded,geometry,uploads,changed},target,phase,width,height,mapped,replace,frames,generations})

def present_result(app: Session, replace: Bool, outcome: V.PresentOutcome) -> V.Action(Session):
  Session{world,target,phase,width,height,mapped,recreate,frames,generations} = app
  match outcome:
    case V.Presented{}: V.Action.pure(Session,Session{world,target,P.Presenting{replace,False{}},width,height,mapped,recreate,frames,generations})
    case V.PresentSurfaceLost{}: V.Action.pure(Session,Session{world,target,P.Presenting{True{},True{}},width,height,mapped,recreate,frames,generations})
    case _: V.Action.pure(Session,Session{world,target,P.Presenting{True{},False{}},width,height,mapped,recreate,frames,generations})

def submitted_ready(context: WSI.Context, frame: P.Frame, app: Session, +index: U32, replace: Bool, status: U32) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,width,height,mapped,recreate,frames,generations} = app
  match target status:
    case Some{+target} 0:
      do V.Action<Session>:
        outcome : V.PresentOutcome <- V.Device.present(device,target_swapchain(target),index,finished,present)
        present_result(Session{world,Some{target},phase,width,height,mapped,recreate,frames,generations},replace,outcome)
    case _ _: V.Action.pure(Session,Session{world,target,phase,width,height,mapped,recreate,frames,generations})

def presented_ready(frame: P.Frame, app: Session, replace: Bool, lost: Bool, status: U32) -> V.Action(Session):
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,width,height,mapped,recreate,frames,generations} = app
  match lost status:
    case False{} 0:
      do V.Action<Session>:
        V.Fence.reset(present)
        V.CommandBuffer.reset(command)
        return Session{world,target,P.Idle{},width,height,mapped,recreate || replace,U32.inc(frames),generations}
    case True{} 0: IO.pure(V.VkResult(Session),Fail{(3294967296,"Surface lost during presentation")})
    case _ _: V.Action.pure(Session,Session{world,target,P.Presenting{replace,lost},width,height,mapped,recreate,frames,generations})

def advance(+frame: P.Frame, app: Session, +context: WSI.Context) -> V.Action(Session):
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,+width,+height,+mapped,replace,frames,generations} = app
  match phase:
    case P.Idle{}: idle(world,target,width,height,mapped,replace,frames,generations,context,frame,Core.drawable(mapped,width,height))
    case P.Acquiring{+index,+suboptimal}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(acquire,W.of_u32(1000000))
        acquired_ready(context,frame,Session{world,target,P.Acquiring{index,suboptimal},width,height,mapped,replace,frames,generations},index,suboptimal,status)
    case P.Submitted{+index,+suboptimal}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(render,W.of_u32(1000000))
        submitted_ready(context,frame,Session{world,target,P.Submitted{index,suboptimal},width,height,mapped,replace,frames,generations},index,suboptimal,status)
    case P.Presenting{+suboptimal,+lost}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(present,W.of_u32(1000000))
        presented_ready(frame,Session{world,target,P.Presenting{suboptimal,lost},width,height,mapped,replace,frames,generations},suboptimal,lost,status)

def log(world: World, +width: U32, +height: U32, mapped: Bool, captured: Bool, +frames: U32, generations: U32) -> V.Action(World):
  World{body,M.Mesh{faces,+count,vs,ix},+camera,controls,+revision,uploaded,geometry,+uploads,changed} = world
  R.Camera{R.Vec3{x,y,z},yaw,pitch} = camera
  do V.Action<World>:
    rows : U32 <- V.debug_live_objects()
    V.Action.lift(Unit,IO.print("STATE rows=" ++ U32.show(rows) ++ " frame=" ++ U32.show(frames) ++ " generation=" ++ U32.show(generations) ++ " revision=" ++ U32.show(revision) ++ " uploads=" ++ U32.show(uploads) ++ " quads=" ++ U32.show(count) ++ " width=" ++ U32.show(width) ++ " height=" ++ U32.show(height) ++ " mapped=" ++ U32.show(Bool.to_u32(mapped)) ++ " captured=" ++ U32.show(Bool.to_u32(captured)) ++ " camera=" ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch))))
    return World{body,M.Mesh{faces,count,vs,ix},camera,controls,revision,uploaded,geometry,uploads,False{}}

def diagnostics(enabled: Bool, world: World, width: U32, height: U32, mapped: Bool, captured: Bool, frames: U32, generations: U32) -> V.Action(World):
  match enabled:
    case False{}: V.Action.pure(World,world)
    case True{}: log(world,width,height,mapped,captured,frames,generations)

def process_events(trace: Bool, +context: WSI.Context, +frame: P.Frame, next: Maybe<World>, target: Maybe<&2,P.Target>, phase: P.Phase, +width: U32, +height: U32, +mapped: Bool, captured: Bool, replace: Bool, +frames: U32, +generations: U32, elapsed: Nat) -> V.Action(Maybe<Session>):
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  match next:
    case None{}: V.Action.pure(Maybe<Session>,None{})
    case Some{world}:
      do V.Action<Maybe<Session>>:
        moved : World <- capture_apply(window,fly(world,elapsed))
        logged : World <- diagnostics(trace,moved,width,height,mapped,captured,frames,generations)
        app : Session <- advance(frame,Session{logged,target,phase,width,height,mapped,replace,frames,generations},context)
        return Some{app}

def mapping(target: Maybe<&2,P.Target>, +window_width: U32, +window_height: U32) -> View.Mapping:
  match target:
    case None{}: View.Mapping{window_width,window_height,window_width,window_height}
    case Some{P.Target{swapchain,images,depth,pass,layout,pipeline,width,height}}:
      View.Mapping{window_width,window_height,width,height}

def snapshot(trace: Bool, app: Session, +context: WSI.Context, frame: P.Frame, state: V.WindowSnapshot, elapsed: Nat) -> V.Action(Maybe<Session>):
  Session{world,+target,phase,old_width,old_height,old_mapped,recreate,frames,generations} = app
  V.WindowSnapshot{+width,+height,+mapped,focused,captured,native_events} = state
  process_events(trace,context,frame,events(native_events,world,mapping(target,width,height)),target,phase,width,height,mapped,captured,recreate || U32.is_ne(width,old_width) || U32.is_ne(height,old_height),frames,generations,elapsed)

def window(context: WSI.Context) -> V.NativeWindow:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  window

def elapsed(previous: Maybe<&2,Nat>, now: Nat) -> Nat:
  match previous:
    case None{}: 0n
    case Some{before}: Nat.min(Nat.sub(now,before),100n)

def wait_time(app: Session) -> U32:
  Session{world,target,phase,width,height,mapped,recreate,frames,generations} = app
  Bool.pick(U32,Core.drawable(mapped,width,height),4,50)

def turn(trace: Bool, +context: WSI.Context, +frame: P.Frame, previous: Maybe<&2,Nat>, app: Session, next: Maybe<Session> -> Nat -> V.Action(Unit)) -> V.Action(Unit):
  Session{world,target,phase,+width,+height,+mapped,recreate,frames,generations} = app
  do V.Action<Unit>:
    state : V.WindowSnapshot <- V.NativeWindow.poll(window(context),Bool.pick(U32,Core.drawable(mapped,width,height),4,50))
    +now : Nat <- V.Action.lift(Nat,IO.now())
    result : Maybe<Session> <- snapshot(trace,Session{world,target,phase,width,height,mapped,recreate,frames,generations},context,frame,state,elapsed(previous,now))
    next(result,now)

def loop(fuel: Nat, next: Maybe<Session>, +trace: Bool, +context: WSI.Context, +frame: P.Frame, previous: Maybe<&2,Nat>) -> V.Action(Unit):
  match fuel next:
    case 0n _: V.Action.pure(Unit,Unit{})
    case _ None{}: V.Action.pure(Unit,Unit{})
    case 1n+rest Some{app}:
      turn(trace,context,frame,previous,app,result => now => loop(rest,result,trace,context,frame,Some{now}))

def device(context: WSI.Context) -> V.Device:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  device

def run(+entry: V.Entry, split: Bool, trace: Bool) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend Vulkan cube | WASD Q/E | RMB look | click carve | Space cut | R reset | Esc",split)
    +frame : P.Frame <- P.frame(device(context))
    loop(4294967295n,Some{Session{initial(M.build(X.Body.solid(3n))),None{},P.Idle{},640,480,False{},True{},0,0}},trace,context,frame,None{})
