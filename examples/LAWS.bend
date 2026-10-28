import Base
import ./window_scene.bend as Scene

law mesh_vertex_words:
  {List.length(&1,U32,Scene.vertices()) == 168n : Nat}

law mesh_index_count:
  {List.length(&1,U32,Scene.indices()) == 42n : Nat}

law mesh_indices_in_bounds:
  {List.all(~&1,~U32,~(i => U32.is_lt(i,28)),Scene.indices()) == True{} : Bool}

law close_wins_over_later_input:
  for camera: Scene.Camera
  {Scene.events([Close{},Key{114,True{}}],Some{camera}) == None{} : Maybe<Scene.Camera>}

law escape_closes:
  for camera: Scene.Camera
  {Scene.events([Key{27,True{}}],Some{camera}) == None{} : Maybe<Scene.Camera>}

law release_preserves_camera:
  for camera: Scene.Camera
  {Scene.events([Key{97,False{}}],Some{camera}) == Some{camera} : Maybe<Scene.Camera>}

law reset_camera:
  for camera: Scene.Camera
  {Scene.key(114,camera) == Scene.initial() : Scene.Camera}
