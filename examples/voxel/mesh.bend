import Base
import ../../deps/bend-voxel/voxel.bend as X
import ../../deps/bend-voxel/material.bend as M
import ../../deps/bend-voxel/render.bend as R

type Mesh is Type:
  Mesh{faces: List<&2,X.Face>, count: U32, vertices: Array<U32>, indices: Array<U32>}

def direction(d: X.Direction) -> U32:
  match d:
    case X.NegX{}: 0
    case X.PosX{}: 1
    case X.NegY{}: 2
    case X.PosY{}: 3
    case X.NegZ{}: 4
    case X.PosZ{}: 5

def rgbd(+rgb: U32, d: U32) -> U32:
  ((rgb >> 16n) .|. ((rgb >> 8n .&. 255) << 8n) .|. ((rgb .&. 255) << 16n) .|. (d << 24n) : U32)

def corner_axes(d: U32, +a: U32, +b: U32) -> X.Cell:
  match d:
    case 0: X.Cell{0,b,a}
    case 1: X.Cell{1,a,b}
    case 2: X.Cell{a,0,b}
    case 3: X.Cell{b,1,a}
    case 4: X.Cell{b,a,0}
    case _: X.Cell{a,b,1}

def corner(d: U32, +i: U32) -> X.Cell:
  corner_axes(d,Bool.pick(U32,Bool.or(U32.is_eq(i,1),U32.is_eq(i,2)),1,0),Bool.pick(U32,(i >= 2 : U32),1,0))

def vertex_at(cell: X.Cell, delta: X.Cell, metadata: U32, material: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  X.Cell{x,y,z} = cell
  X.Cell{dx,dy,dz} = delta
  words[offset] <- F32.bits(U32.to_f32((x + dx : U32)))
  words[(offset + 1 : U32)] <- F32.bits(U32.to_f32((y + dy : U32)))
  words[(offset + 2 : U32)] <- F32.bits(U32.to_f32((z + dz : U32)))
  words[(offset + 3 : U32)] <- metadata
  words[(offset + 4 : U32)] <- material
  words

def vertex(cell: X.Cell, d: U32, i: U32, metadata: U32, material: U32, offset: U32, words: Array<U32>) -> Array<U32>:
  vertex_at(cell,corner(d,i),metadata,material,offset,words)

def quad(+cell: X.Cell, +d: U32, +metadata: U32, +material: U32, +base: U32, words: Array<U32>) -> Array<U32>:
  words = vertex(cell,d,0,metadata,material,base,words)
  words = vertex(cell,d,1,metadata,material,(base + 5 : U32),words)
  words = vertex(cell,d,2,metadata,material,(base + 10 : U32),words)
  vertex(cell,d,3,metadata,material,(base + 15 : U32),words)

def index_quad(+base: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  words[offset] <- base
  words[(offset + 1 : U32)] <- (base + 1 : U32)
  words[(offset + 2 : U32)] <- (base + 2 : U32)
  words[(offset + 3 : U32)] <- (base + 2 : U32)
  words[(offset + 4 : U32)] <- (base + 3 : U32)
  words[(offset + 5 : U32)] <- base
  words

def count(faces: List<&2,X.Face>) -> U32:
  match faces:
    case Nil{}: 0
    case Con{face,rest}: (1 + count(rest) : U32)

def capacity(fuel: Nat, +n: U32, +size: U32, +depth: Nat) -> Nat:
  match fuel:
    case 0n: depth
    case 1n+rest:
      +grow = (size < n : U32)
      capacity(rest,n,Bool.pick(U32,grow,(size * 2 : U32),size),Bool.pick(Nat,grow,1n+depth,depth))


def vertices(faces: List<&2,X.Face>, +palette: M.Palette, +base: U32, words: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}: words
    case Con{X.Face{cell,+d,+material},rest}:
      vertices(rest,palette,(base + 20 : U32),quad(cell,direction(d),rgbd(M.Palette.surface(palette,material,R.Face.light(d)),direction(d)),material,base,words))
    case Con{X.Rectangle{cell,d,material,w,h},rest}: words

def indices(faces: List<&2,X.Face>, +base: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}: words
    case Con{face,rest}: indices(rest,(base + 4 : U32),(offset + 6 : U32),index_quad(base,offset,words))

def pack(+faces: List<&2,X.Face>) -> Mesh:
  +n = count(faces)
  vs = vertices(faces,M.Palette.build(),0,Array.new(U32,capacity(31n,(n * 20 : U32),1,0n),0))
  ix = indices(faces,0,0,Array.new(U32,capacity(31n,(n * 6 : U32),1,0n),0))
  Mesh{faces,n,vs,ix}

def built(pair: X.Body & X.Surface) -> X.Body & Mesh:
  (body,X.Surface{faces}) = pair
  (body,pack(faces))

def build(body: X.Body) -> X.Body & Mesh:
  built(X.Surface.build(body))

def material_read(pair: Array<U32> & U32) -> U32:
  (words,value) = pair
  value

def material_word(words: Array<U32>) -> U32:
  material_read(Array.get(U32,words,4))
