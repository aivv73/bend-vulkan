import Base
import ../../Vulkan.bend as V
import ../../src/core.bend as Core
import ../../deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-voxel/main.bend as Controls
import ../../deps/bend-voxel/atelier.bend as AtelierBody
import ../../deps/bend-voxel/render.bend as R
import ../../deps/bend-voxel/voxel.bend as X
import ../window.bend as WSI
import ../buffer_roundtrip.bend as D
import ./mesh.bend as M
import ./exterior.bend as Exterior
import ./renderer.bend as GPU
import ./presentation.bend as P
import ./viewport.bend as View
import ./scene.bend as Scene
import ./appearance.bend as A

type Original is Data:
  Cube{}
  Atelier{}
type Pointer is Data:
  Pointer{x: U32, y: U32}

type World is Type:
  World{body: X.Body, mesh: M.Mesh, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer, changed: Bool}
type PendingWorld is Type:
  PendingWorld{body: X.Body, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer, changed: Bool}
type Session is Type:
  Session{world: World, target: Maybe<&2,P.Target>, phase: P.Phase, width: U32, height: U32, mapped: Bool, recreate: Bool, frames: U32, generations: U32, scene: Scene.Group}

def built(pair: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(X.Body & M.Mesh):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(X.Body & M.Mesh),Fail{(1,Exterior.error_show(error))})
    case Done{mesh}: V.Action.pure(X.Body & M.Mesh,(body,mesh))

def original_body(original: Original) -> X.Body:
  match original:
    case Cube{}: X.Body.solid(3n)
    case Atelier{}: AtelierBody.body()

def original_camera(original: Original) -> R.Camera:
  match original:
    case Cube{}: R.Camera.initial()
    case Atelier{}: R.Camera.atelier()

def initial_world(pair: X.Body & M.Mesh) -> World:
  (body,mesh) = pair
  World{body,mesh,R.Camera.initial(),Controls.Controls.initial(),0,Cube{},Pointer{320,240},True{}}

def edited_world(pair: X.Body & M.Mesh, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer) -> World:
  (body,mesh) = pair
  World{body,mesh,camera,controls,U32.inc(revision),original,pointer,True{}}

def initial(result: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & M.Mesh <- built(result)
    return initial_world(pair)

def edited(result: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & M.Mesh <- built(result)
    return edited_world(pair,camera,controls,revision,original,pointer)

def changed(world: World, sphere: X.MetricSphere) -> V.Action(World):
  World{body,mesh,camera,controls,revision,+original,pointer,old} = world
  edited(M.build(X.Body.cut(body,sphere)),camera,controls,revision,original,pointer)

def picked(world: World, hit: Maybe<&2,X.MetricSphere>) -> V.Action(World):
  match hit:
    case None{}: V.Action.pure(World,world)
    case Some{sphere}: changed(world,sphere)

def click(world: World, +view: View.Viewport, +x: U32, +y: U32) -> V.Action(World):
  World{body,mesh,+camera,+controls,revision,+original,pointer,old} = world
  M.Mesh{+faces,size,bounds,vs,ix} = mesh
  View.Viewport{+width,+height} = view
  picked(World{body,M.Mesh{faces,size,bounds,vs,ix},camera,controls,revision,original,pointer,old},View.target(view,camera,faces,Bool.pick(U32,Controls.Controls.capture(controls),(width / 2 : U32),x),Bool.pick(U32,Controls.Controls.capture(controls),(height / 2 : U32),y)))

def reset(world: World) -> V.Action(World):
  World{body,mesh,camera,controls,revision,+original,pointer,old} = world
  edited(M.build(original_body(original)),camera,controls,revision,original,pointer)

def key(world: World, code: U32, down: Bool) -> World:
  World{body,mesh,camera,controls,revision,+original,pointer,old} = world
  World{body,mesh,camera,Controls.Controls.key(code,down,controls),revision,original,pointer,old}

def capture(world: World, looking: Bool) -> World:
  World{body,mesh,camera,controls,revision,+original,pointer,old} = world
  World{body,mesh,camera,Controls.Controls.look(controls,looking),revision,original,pointer,old}

def look_active(active: Bool, world: World, dx: F32, dy: F32) -> World:
  match active world:
    case False{} _: world
    case True{} World{body,mesh,camera,controls,revision,original,pointer,old}:
      World{body,mesh,R.Camera.look(camera,dx,dy),controls,revision,original,pointer,True{}}

def look(world: World, dx: F32, dy: F32) -> World:
  World{body,mesh,camera,+controls,revision,+original,pointer,old} = world
  look_active(Controls.Controls.capture(controls),World{body,mesh,camera,controls,revision,original,pointer,old},dx,dy)

def click_point(world: World, view: View.Viewport, point: U32 & U32) -> V.Action(World):
  (x,y) = point
  click(world,view,x,y)

def mapped_click(world: World, +mapping: View.Mapping, x: U32, y: U32) -> V.Action(World):
  View.Mapping{ww,wh,width,height} = mapping
  click_point(world,View.Viewport{width,height},View.map_point(mapping,x,y))

def pointer(world: World, x: U32, y: U32) -> World:
  World{body,mesh,camera,controls,revision,original,old,changed} = world
  World{body,mesh,camera,controls,revision,original,Pointer{x,y},True{}}

def hover_point(+view: View.Viewport, +camera: R.Camera, faces: List<&2,X.Face>, +captured: Bool, point: U32 & U32) -> Maybe<&2,X.MetricSphere>:
  View.Viewport{+width,+height} = view
  (x,y) = point
  View.target(view,camera,faces,Bool.pick(U32,captured,(width / 2 : U32),x),Bool.pick(U32,captured,(height / 2 : U32),y))

def hover(+view: View.Mapping, camera: R.Camera, controls: Controls.Controls, point: Pointer, faces: List<&2,X.Face>) -> Maybe<&2,X.MetricSphere>:
  View.Mapping{ww,wh,w,h} = view
  Pointer{x,y} = point
  hover_point(View.Viewport{w,h},camera,faces,Controls.Controls.capture(controls),View.map_point(view,x,y))

def space(world: World, +view: View.Mapping) -> V.Action(World):
  match world:
    case World{body,mesh,camera,controls,revision,Cube{},point,dirty}:
      changed(World{body,mesh,camera,controls,revision,Cube{},point,dirty},X.MetricSphere.brush(X.PointCm.cell(X.Cell{6,6,6})))
    case World{body,M.Mesh{+faces,size,bounds,vs,ix},+camera,+controls,revision,Atelier{},+point,changed}:
      picked(World{body,M.Mesh{faces,size,bounds,vs,ix},camera,controls,revision,Atelier{},point,changed},hover(view,camera,controls,point,faces))

def continued(action: V.Action(World)) -> V.Action(Maybe<World>):
  do V.Action<Maybe<World>>:
    world : World <- action
    return Some{world}

def event(event: Event, world: World, view: View.Mapping) -> V.Action(Maybe<World>):
  match event:
    case Close{}: V.Action.pure(Maybe<World>,None{})
    case Key{27,True{}}: V.Action.pure(Maybe<World>,None{})
    case Key{32,True{}}: continued(space(world,view))
    case Key{114,True{}}: continued(reset(world))
    case Key{82,True{}}: continued(reset(world))
    case Key{code,down}: V.Action.pure(Maybe<World>,Some{key(world,code,down)})
    case Mouse{+x,+y,1,down}: V.Action.pure(Maybe<World>,Some{capture(pointer(world,x,y),down)})
    case Mouse{+x,+y,0,True{}}: continued(mapped_click(pointer(world,x,y),view,x,y))
    case Mouse{+x,+y,button,down}: V.Action.pure(Maybe<World>,Some{pointer(world,x,y)})
    case Move{x,y}: V.Action.pure(Maybe<World>,Some{pointer(world,x,y)})
    case Look{dx,dy}: V.Action.pure(Maybe<World>,Some{look(world,dx,dy)})
    case _: V.Action.pure(Maybe<World>,Some{world})

def events_next(result: Maybe<World>, next: World -> V.Action(Maybe<World>)) -> V.Action(Maybe<World>):
  match result:
    case None{}: V.Action.pure(Maybe<World>,None{})
    case Some{world}: next(world)

def events(xs: List<Event>, world: World, +view: View.Mapping) -> V.Action(Maybe<World>):
  match xs:
    case Nil{}: V.Action.pure(Maybe<World>,Some{world})
    case Con{head,rest}:
      do V.Action<Maybe<World>>:
        result : Maybe<World> <- event(head,world,view)
        events_next(result,next => events(rest,next,view))

def fly(world: World, +elapsed: Nat) -> World:
  World{body,mesh,+camera,+controls,revision,+original,pointer,old} = world
  +next = Controls.Controls.fly(controls,camera,elapsed)
  World{body,mesh,next,controls,revision,original,pointer,old || Bool.not(R.Camera.equal(camera,next))}

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
  World{body,mesh,camera,old,revision,original,pointer,changed} = world
  (controls,request) = result
  capture_requested(window,World{body,mesh,camera,controls,revision,original,pointer,changed},request)

def capture_apply(window: V.NativeWindow, world: World) -> V.Action(World):
  World{body,mesh,camera,+controls,revision,original,pointer,changed} = world
  capture_result(window,World{body,mesh,camera,controls,revision,original,pointer,changed},Controls.Controls.request(controls))

def target_destroy(device: V.Device, target: Maybe<&2,P.Target>) -> V.Action(Unit):
  match target:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{target}: P.destroy(device,target)

def target_swapchain(target: P.Target) -> V.Swapchain:
  P.Target{swapchain,images,depth,pass,layout,pipeline,width,height,format,production} = target
  swapchain

def production_target(device: V.Device, target: P.Target, assets: Scene.Assets, original: Original) -> V.Action(P.Target):
  match original:
    case Cube{}: V.Action.pure(P.Target,target)
    case Atelier{}: P.promote(device,target,assets)

def record_world(+device: V.Device, frame: P.Frame, target: P.Target, acquisition: V.Acquisition, index: U32, camera: R.Camera, original: Original, +scene: Scene.Group, words: Maybe<Array<U32>>) -> V.Action(Unit):
  match original:
    case Cube{}:
      Scene.Group{a,geometry,r,u} = scene
      P.record(device,frame,target,acquisition,index,camera,geometry)
    case Atelier{}:
      do V.Action<Unit>:
        Scene.upload(device,Scene.assets(scene),words)
        P.record_production(device,frame,target,acquisition,index,scene)

def idle_target(+context: WSI.Context, frame: P.Frame, world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, frames: U32, +generations: U32, +scene: Scene.Group, replace: Bool) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  World{body,mesh,camera,controls,revision,+original,point,changed} = world
  match replace:
    case True{}:
      do V.Action<Session>:
        target_destroy(device,target)
        raw : P.Target <- P.build(context,width,height)
        +next : P.Target <- production_target(device,raw,Scene.assets(scene),original)
        return Session{World{body,mesh,camera,controls,revision,original,point,changed},Some{next},P.Idle{},width,height,mapped,False{},frames,U32.inc(generations),scene}
    case False{}: V.Action.pure(Session,Session{World{body,mesh,camera,controls,revision,original,point,changed},target,P.Idle{},width,height,mapped,False{},frames,generations,scene})

def acquire_result(world: World, +target: P.Target, +width: U32, +height: U32, +mapped: Bool, frames: U32, generations: U32, scene: Scene.Group, outcome: V.AcquireOutcome) -> V.Action(Session):
  match outcome:
    case V.Acquired{acquisition,index,suboptimal}: V.Action.pure(Session,Session{world,Some{target},P.Acquiring{acquisition,index,suboptimal},width,height,mapped,False{},frames,generations,scene})
    case V.AcquireOutOfDate{}: V.Action.pure(Session,Session{world,Some{target},P.Idle{},width,height,mapped,True{},frames,generations,scene})
    case V.AcquireSurfaceLost{}: IO.pure(V.VkResult(Session),Fail{(3294967296,"Surface lost during acquisition")})
    case _: V.Action.pure(Session,Session{world,Some{target},P.Idle{},width,height,mapped,False{},frames,generations,scene})

def begin_ready(context: WSI.Context, frame: P.Frame, world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, frames: U32, generations: U32, scene: Scene.Group) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  match target:
    case None{}: V.Action.pure(Session,Session{world,None{},P.Idle{},width,height,mapped,True{},frames,generations,scene})
    case Some{+target}:
      do V.Action<Session>:
        outcome : V.AcquireOutcome <- V.Device.acquire(device,target_swapchain(target),acquire,W.of_u32(1000000))
        acquire_result(world,target,width,height,mapped,frames,generations,scene,outcome)

def idle_prepared(app: Session, context: WSI.Context, frame: P.Frame) -> V.Action(Session):
  Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene} = app
  begin_ready(context,frame,world,target,width,height,mapped,frames,generations,scene)

def idle(world: World, target: Maybe<&2,P.Target>, +width: U32, +height: U32, +mapped: Bool, replace: Bool, frames: U32, generations: U32, scene: Scene.Group, +context: WSI.Context, +frame: P.Frame, drawable: Bool) -> V.Action(Session):
  match drawable:
    case False{}: V.Action.pure(Session,Session{world,target,P.Idle{},width,height,mapped,replace,frames,generations,scene})
    case True{}:
      do V.Action<Session>:
        app : Session <- idle_target(context,frame,world,target,width,height,mapped,frames,generations,scene,replace)
        idle_prepared(app,context,frame)

def frame_extent(bounds: Maybe<&2,M.Extent>) -> U32:
  match bounds:
    case None{}: 0
    case Some{M.Extent{low,X.Cell{x,y,z}}}: U32.max(x,U32.max(y,z))

def output(+format: U32) -> A.Output:
  Bool.pick(A.Output,U32.is_eq(format,43) || U32.is_eq(format,50),A.Srgb{},A.Unorm{})

def record_ready(+context: WSI.Context, +frame: P.Frame, pending: PendingWorld, +width: U32, +height: U32, mapped: Bool, replace: Bool, frames: U32, generations: U32, +target: P.Target, +acquisition: V.Acquisition, +index: U32, suboptimal: Bool, installed: Scene.Group & M.Mesh) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  PendingWorld{body,+camera,+controls,revision,+original,+point,changed} = pending
  P.Target{sc,images,depth,pass,layout,pipeline,+tw,+th,format,production} = target
  (+scene,M.Mesh{+faces,size,+bounds,vs,ix}) = installed
  do V.Action<Session>:
    record_world(device,frame,target,acquisition,index,camera,original,scene,A.encode(A.FrameInput{R.Camera.basis(camera),tw,th,frame_extent(bounds),Scene.palette(Scene.assets(scene)),hover(View.Mapping{width,height,tw,th},camera,controls,point,faces),output(format),A.Shaded{}}))
    return Session{World{body,M.Mesh{faces,size,bounds,vs,ix},camera,controls,revision,original,point,False{}},Some{target},P.Submitted{acquisition,index,suboptimal},width,height,mapped,replace,frames,generations,scene}

def acquired_ready(+context: WSI.Context, +frame: P.Frame, app: Session, acquisition: V.Acquisition, +index: U32, suboptimal: Bool, status: U32) -> V.Action(Session):
  WSI.Context{window,+instance,+physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{World{body,mesh,camera,controls,+revision,original,point,changed},target,phase,width,height,mapped,replace,frames,generations,+scene} = app
  match target status:
    case Some{+target} 0:
      do V.Action<Session>:
        V.Fence.reset(acquire)
        installed : Scene.Group & M.Mesh <- Scene.install(instance,physical,device,scene,revision,mesh)
        record_ready(context,frame,PendingWorld{body,camera,controls,revision,original,point,changed},width,height,mapped,replace,frames,generations,target,acquisition,index,suboptimal,installed)
    case _ _:
      V.Action.pure(Session,Session{World{body,mesh,camera,controls,revision,original,point,changed},target,phase,width,height,mapped,replace,frames,generations,scene})

def present_result(app: Session, replace: Bool, outcome: V.PresentOutcome) -> V.Action(Session):
  Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene} = app
  match outcome:
    case V.Presented{}: V.Action.pure(Session,Session{world,target,P.Presenting{replace,False{}},width,height,mapped,recreate,frames,generations,scene})
    case V.PresentSurfaceLost{}: V.Action.pure(Session,Session{world,target,P.Presenting{True{},True{}},width,height,mapped,recreate,frames,generations,scene})
    case _: V.Action.pure(Session,Session{world,target,P.Presenting{True{},False{}},width,height,mapped,recreate,frames,generations,scene})

def submitted_ready(context: WSI.Context, frame: P.Frame, app: Session, acquisition: V.Acquisition, +index: U32, replace: Bool, status: U32) -> V.Action(Session):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene} = app
  match target status:
    case Some{+target} 0:
      do V.Action<Session>:
        outcome : V.PresentOutcome <- V.Device.present(device,acquisition,finished,present)
        present_result(Session{world,Some{target},phase,width,height,mapped,recreate,frames,generations,scene},replace,outcome)
    case _ _: V.Action.pure(Session,Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene})

def presented_ready(frame: P.Frame, app: Session, replace: Bool, lost: Bool, status: U32) -> V.Action(Session):
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene} = app
  match lost status:
    case False{} 0:
      do V.Action<Session>:
        V.Fence.reset(present)
        V.CommandBuffer.reset(command)
        return Session{world,target,P.Idle{},width,height,mapped,recreate || replace,U32.inc(frames),generations,scene}
    case True{} 0: IO.pure(V.VkResult(Session),Fail{(3294967296,"Surface lost during presentation")})
    case _ _: V.Action.pure(Session,Session{world,target,P.Presenting{replace,lost},width,height,mapped,recreate,frames,generations,scene})

def advance(+frame: P.Frame, app: Session, +context: WSI.Context) -> V.Action(Session):
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Session{world,target,phase,+width,+height,+mapped,replace,frames,generations,scene} = app
  match phase:
    case P.Idle{}: idle(world,target,width,height,mapped,replace,frames,generations,scene,context,frame,Core.drawable(mapped,width,height))
    case P.Acquiring{+acquisition,+index,+suboptimal}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(acquire,W.of_u32(1000000))
        acquired_ready(context,frame,Session{world,target,P.Acquiring{acquisition,index,suboptimal},width,height,mapped,replace,frames,generations,scene},acquisition,index,suboptimal,status)
    case P.Submitted{+acquisition,+index,+suboptimal}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(render,W.of_u32(1000000))
        submitted_ready(context,frame,Session{world,target,P.Submitted{acquisition,index,suboptimal},width,height,mapped,replace,frames,generations,scene},acquisition,index,suboptimal,status)
    case P.Presenting{+suboptimal,+lost}:
      do V.Action<Session>:
        status : U32 <- V.Fence.wait(present,W.of_u32(1000000))
        presented_ready(frame,Session{world,target,P.Presenting{suboptimal,lost},width,height,mapped,replace,frames,generations,scene},suboptimal,lost,status)

def log(scene: Scene.Group, world: World, +width: U32, +height: U32, mapped: Bool, captured: Bool, +frames: U32, generations: U32) -> V.Action(World):
  Scene.Group{a,geo,+installed,+uploads} = scene
  World{body,M.Mesh{faces,+size,bounds,vs,ix},+camera,controls,+revision,original,pointer,changed} = world
  M.PackedSize{count,vc,ic,vw,iw,vb,ib,vsiz,isiz,vd,id} = size
  R.Camera{R.Vec3{x,y,z},yaw,pitch} = camera
  do V.Action<World>:
    rows : U32 <- V.debug_live_objects()
    V.Action.lift(Unit,IO.print("STATE rows=" ++ U32.show(rows) ++ " frame=" ++ U32.show(frames) ++ " generation=" ++ U32.show(generations) ++ " revision=" ++ U32.show(revision) ++ " installed=" ++ U32.show(installed) ++ " uploads=" ++ U32.show(uploads) ++ " quads=" ++ U32.show(count) ++ " width=" ++ U32.show(width) ++ " height=" ++ U32.show(height) ++ " mapped=" ++ U32.show(Bool.to_u32(mapped)) ++ " captured=" ++ U32.show(Bool.to_u32(captured)) ++ " camera=" ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch))))
    return World{body,M.Mesh{faces,size,bounds,vs,ix},camera,controls,revision,original,pointer,changed}

def diagnostics(enabled: Bool, scene: Scene.Group, world: World, width: U32, height: U32, mapped: Bool, captured: Bool, frames: U32, generations: U32) -> V.Action(World):
  match enabled:
    case False{}: V.Action.pure(World,world)
    case True{}: log(scene,world,width,height,mapped,captured,frames,generations)

def process_events(trace: Bool, +context: WSI.Context, +frame: P.Frame, next: Maybe<World>, target: Maybe<&2,P.Target>, phase: P.Phase, +width: U32, +height: U32, +mapped: Bool, captured: Bool, replace: Bool, +frames: U32, +generations: U32, +scene: Scene.Group, elapsed: Nat) -> V.Action(Maybe<Session>):
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  match next:
    case None{}: V.Action.pure(Maybe<Session>,None{})
    case Some{world}:
      do V.Action<Maybe<Session>>:
        moved : World <- capture_apply(window,fly(world,elapsed))
        logged : World <- diagnostics(trace,scene,moved,width,height,mapped,captured,frames,generations)
        app : Session <- advance(frame,Session{logged,target,phase,width,height,mapped,replace,frames,generations,scene},context)
        return Some{app}

def mapping(target: Maybe<&2,P.Target>, +window_width: U32, +window_height: U32) -> View.Mapping:
  match target:
    case None{}: View.Mapping{window_width,window_height,window_width,window_height}
    case Some{P.Target{swapchain,images,depth,pass,layout,pipeline,width,height,format,production}}:
      View.Mapping{window_width,window_height,width,height}

def snapshot(trace: Bool, app: Session, +context: WSI.Context, frame: P.Frame, state: V.WindowSnapshot, elapsed: Nat) -> V.Action(Maybe<Session>):
  Session{world,+target,phase,old_width,old_height,old_mapped,recreate,frames,generations,scene} = app
  V.WindowSnapshot{+width,+height,+mapped,focused,captured,native_events} = state
  do V.Action<Maybe<Session>>:
    next : Maybe<World> <- events(native_events,world,mapping(target,width,height))
    process_events(trace,context,frame,next,target,phase,width,height,mapped,captured,recreate || U32.is_ne(width,old_width) || U32.is_ne(height,old_height),frames,generations,scene,elapsed)

def window(context: WSI.Context) -> V.NativeWindow:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  window

def elapsed(previous: Maybe<&2,Nat>, now: Nat) -> Nat:
  match previous:
    case None{}: 0n
    case Some{before}: Nat.min(Nat.sub(now,before),100n)

def wait_time(app: Session) -> U32:
  Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene} = app
  Bool.pick(U32,Core.drawable(mapped,width,height),4,50)

def turn(trace: Bool, +context: WSI.Context, +frame: P.Frame, previous: Maybe<&2,Nat>, app: Session, next: Maybe<Session> -> Nat -> V.Action(Unit)) -> V.Action(Unit):
  Session{world,target,phase,+width,+height,+mapped,recreate,frames,generations,scene} = app
  do V.Action<Unit>:
    state : V.WindowSnapshot <- V.NativeWindow.poll(window(context),Bool.pick(U32,Core.drawable(mapped,width,height),4,50))
    +now : Nat <- V.Action.lift(Nat,IO.now())
    result : Maybe<Session> <- snapshot(trace,Session{world,target,phase,width,height,mapped,recreate,frames,generations,scene},context,frame,state,elapsed(previous,now))
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

def initial_selected(pair: X.Body & M.Mesh, +original: Original) -> World:
  (body,mesh) = pair
  World{body,mesh,original_camera(original),Controls.Controls.initial(),0,original,Pointer{320,240},True{}}

def initial_scene(+original: Original) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & M.Mesh <- built(M.build(original_body(original)))
    return initial_selected(pair,original)

def scene_create(context: WSI.Context) -> V.Action(Scene.Group):
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  Scene.create(instance,physical,device)

def announce(context: WSI.Context, enabled: Bool) -> V.Action(Unit):
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  match enabled:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}: V.Action.lift(Unit,IO.print("Queues " ++ U32.show(g) ++ " " ++ U32.show(p)))

def run(+entry: V.Entry, split: Bool, +trace: Bool, original: Original) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend Vulkan | WASD Q/E | RMB look | click carve | Space cut | R reset | Esc",split)
    announce(context,trace)
    +frame : P.Frame <- P.frame(device(context))
    +scene : Scene.Group <- scene_create(context)
    world : World <- initial_scene(original)
    loop(4294967295n,Some{Session{world,None{},P.Idle{},640,480,False{},True{},0,0,scene}},trace,context,frame,None{})
