import Base
import ./mesh.bend as M
import ../../deps/bend-voxel/voxel.bend as X
import ../../deps/bend-voxel/render.bend as R
import ../../deps/bend-voxel/material.bend as P

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def same_cell(a: X.Cell, b: X.Cell) -> Bool:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w)

def occurrences(fs: List<&2,X.Face>, +cell: X.Cell, +d: U32, +mat: U32) -> U32:
  match fs:
    case Nil{}: 0
    case Con{X.Face{c,dir,m},rest}:
      (Bool.pick(U32,same_cell(cell,c) && U32.is_eq(d,M.direction(dir)) && U32.is_eq(mat,m),1,0) + occurrences(rest,cell,d,mat) : U32)
    case Con{X.Rectangle{c,dir,m,w,h},rest}: 4294967295

def lookup(tree: X.Snapshot, +index: U32, +span: U32) -> U32:
  match tree:
    case X.Leaf{m}: m
    case X.Node{left,right}:
      +half = (span / 2 : U32)
      (lookup(left,(index % half : U32),half) * Bool.pick(U32,(index < half : U32),1,0) + lookup(right,(index % half : U32),half) * Bool.pick(U32,(index >= half : U32),1,0) : U32)

def read(tree: X.Snapshot, +side: U32, cell: X.Cell) -> U32:
  X.Cell{+x,+y,+z} = cell
  (lookup(tree,(x + side * y + side * side * z : U32),(side * side * side : U32)) * Bool.pick(U32,((x < side) && (y < side) && (z < side) : U32),1,0) : U32)

def neighbor(cell: X.Cell, d: U32) -> X.Cell:
  X.Cell{+x,+y,+z} = cell
  match d:
    case 0: X.Cell{(x - 1 : U32),y,z}
    case 1: X.Cell{(x + 1 : U32),y,z}
    case 2: X.Cell{x,(y - 1 : U32),z}
    case 3: X.Cell{x,(y + 1 : U32),z}
    case 4: X.Cell{x,y,(z - 1 : U32)}
    case _: X.Cell{x,y,(z + 1 : U32)}

def enumerate(fuel: Nat, +index: U32, +side: U32, +tree: X.Snapshot, +fs: List<&2,X.Face>, +total: U32, +ok: Bool) -> U32 & Bool:
  match fuel:
    case 0n: (total,ok)
    case 1n+rest:
      +n = (index / 6 : U32)
      +d = (index % 6 : U32)
      +cell = {X.Cell{(n % side : U32),((n / side) % side : U32),(n / (side * side) : U32)} : X.Cell}
      +material = read(tree,side,cell)
      +exposed = U32.is_ne(material,0) && U32.is_eq(read(tree,side,neighbor(cell,d)),0)
      +expected = Bool.pick(U32,exposed,1,0)
      enumerate(rest,(index + 1 : U32),side,tree,fs,(total + expected : U32),ok && U32.is_eq(occurrences(fs,cell,d,material),expected))

def axis_unit(+v: F32) -> Bool:
  F32.is_eq(v,0.0) || F32.is_eq(v,1.0)

def on_delta(+d: X.Direction, +a: F32, +b: F32, +c: F32) -> Bool:
  axis_unit(a) && axis_unit(b) && axis_unit(c) && F32.is_eq(R.Vec3.dot(R.Vec3{a,b,c},R.Face.normal(d)),Bool.pick(F32,(M.direction(d) % 2 > 0 : U32),1.0,0.0))

def on_face(cell: X.Cell, d: X.Direction, point: R.Vec3) -> Bool:
  X.Cell{x,y,z} = cell
  R.Vec3{px,py,pz} = point
  on_delta(d,(px - U32.to_f32(x) : F32),(py - U32.to_f32(y) : F32),(pz - U32.to_f32(z) : F32))

def sub(a: R.Vec3, b: R.Vec3) -> R.Vec3:
  R.Vec3.add(a,R.Vec3.scale(b,F32.neg(1.0)))

def winding(+a: R.Vec3, +b: R.Vec3, +c: R.Vec3, d: X.Direction) -> Bool:
  F32.is_eq(R.Vec3.dot(R.Vec3.cross(sub(b,a),sub(c,a)),R.Face.normal(d)),1.0)

def quad_ok(+cell: X.Cell, +d: X.Direction, +a: R.Vec3, +b: R.Vec3, +c: R.Vec3, +e: R.Vec3) -> Bool:
  on_face(cell,d,a) && on_face(cell,d,b) && on_face(cell,d,c) && on_face(cell,d,e) && winding(a,b,c,d) && winding(c,e,a,d) && F32.is_eq(R.Vec3.dot(sub(c,a),sub(c,a)),2.0)

def packed(fs: List<&2,X.Face>, vs: List<U32>, ix: List<U32>, +i: U32, +palette: P.Palette, +ok: Bool) -> Bool:
  match fs vs ix:
    case Nil{} _ _: ok
    case Con{X.Face{+cell,+d,+mat},rest} ax <> ay <> az <> ac <> am <> bx <> by <> bz <> bc <> bm <> cx <> cy <> cz <> cc <> cm <> ex <> ey <> ez <> ec <> em <> tail +ia <> ib <> +ic <> id <> ie <> iff <> it:
      +color = M.rgbd(P.Palette.surface(palette,mat,R.Face.light(d)),M.direction(d))
      +metadata = U32.is_eq(ac,color) && U32.is_eq(bc,color) && U32.is_eq(cc,color) && U32.is_eq(ec,color) && U32.is_eq(am,mat) && U32.is_eq(bm,mat) && U32.is_eq(cm,mat) && U32.is_eq(em,mat)
      +indices = U32.is_eq(ia,(i * 4 : U32)) && U32.is_eq(ib,(i * 4 + 1 : U32)) && U32.is_eq(ic,(i * 4 + 2 : U32)) && U32.is_eq(id,ic) && U32.is_eq(ie,(i * 4 + 3 : U32)) && U32.is_eq(iff,ia)
      packed(rest,tail,it,(i + 1 : U32),palette,ok && metadata && indices && quad_ok(cell,d,R.Vec3{float(ax),float(ay),float(az)},R.Vec3{float(bx),float(by),float(bz)},R.Vec3{float(cx),float(cy),float(cz)},R.Vec3{float(ex),float(ey),float(ez)}))
    case _ _ _: False{}

def check_counts(+count: U32, left: U32 & Bool, right: U32 & Bool) -> Bool:
  (a,ok) = left
  (b,valid) = right
  ok && valid && U32.is_eq(count,(a + b : U32))

def coverage(+side: U32, +tree: X.Snapshot, +fs: List<&2,X.Face>, count: U32) -> Bool:
  +half = (side * side * side * 3 : U32)
  a b = enumerate(U32.to_nat(half),0,side,tree,fs,0,True{}) enumerate(U32.to_nat(half),half,side,tree,fs,0,True{})
  check_counts(count,a,b)

def check_arrays(+fs: List<&2,X.Face>, +count: U32, vs: Array<U32> & Array<U32>, ix: Array<U32> & Array<U32>, tree: X.Snapshot, +side: U32) -> M.Mesh & Bool:
  (vertices,vcopy) = vs
  (indices,icopy) = ix
  coverage_ok = coverage(side,tree,fs,count)
  geometry = packed(fs,Array.to_list(~U32,vcopy),Array.to_list(~U32,icopy),0,P.Palette.build(),True{})
  (M.Mesh{fs,count,vertices,indices},coverage_ok && geometry)

def check_mesh(mesh: M.Mesh, tree: X.Snapshot, side: U32) -> M.Mesh & Bool:
  M.Mesh{fs,count,vs,ix} = mesh
  check_arrays(fs,count,Array.clone(U32,vs),Array.clone(U32,ix),tree,side)

def checked_dense(+side: U32, pair: Array<U32> & X.Snapshot, mesh: M.Mesh) -> X.Body & (M.Mesh & Bool):
  (cells,tree) = pair
  (X.Body{side,cells},check_mesh(mesh,tree,side))

def checked(body: X.Body, mesh: M.Mesh) -> X.Body & (M.Mesh & Bool):
  match body:
    case X.Body{side,cells}: checked_dense(side,X.Snapshot.of(cells),mesh)
    case X.Cuboids{boxes}: (X.Cuboids{boxes},(mesh,False{}))

def integer_sub(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  X.Cell{(x - u : U32),(y - v : U32),(z - w : U32)}

def integer_cross(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{+x,+y,+z} = a
  X.Cell{+u,+v,+w} = b
  X.Cell{(y * w - z * v : U32),(z * u - x * w : U32),(x * v - y * u : U32)}

def quad_normal(+d: U32) -> X.Cell:
  integer_cross(integer_sub(M.corner(d,1),M.corner(d,0)),integer_sub(M.corner(d,2),M.corner(d,0)))

def quad_second_normal(+d: U32) -> X.Cell:
  integer_cross(integer_sub(M.corner(d,3),M.corner(d,2)),integer_sub(M.corner(d,0),M.corner(d,2)))

def indices_bounded(indices: List<U32>, +limit: U32) -> Bool:
  match indices:
    case Nil{}: True{}
    case index <> rest: (index < limit : U32) && indices_bounded(rest,limit)

def fixture_index_bounds(fuel: Nat, +face: U32) -> Bool:
  match fuel:
    case 0n: True{}
    case 1n+rest:
      indices_bounded(Array.to_list(~U32,M.index_quad((face * 4 : U32),0,[0 : U32^3n])),((face + 1) * 4 : U32)) && fixture_index_bounds(rest,(face + 1 : U32))
