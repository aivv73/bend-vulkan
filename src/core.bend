import Base
import ../deps/bend-collections/src/math/u64.bend as W

def DeviceSize() -> Data:
  W.U64

def size_words(value: W.U64) -> U32 & U32:
  W.U64{lo, hi} = value
  (lo, hi)

def size_from_words(words: U32 & U32) -> W.U64:
  (lo, hi) = words
  W.U64{lo, hi}

def whole_size() -> W.U64:
  W.U64{4294967295, 4294967295}

def make_api_version(variant: U32, major: U32, minor: U32, patch: U32) -> U32:
  U32.or(U32.shln(variant, 29n), U32.or(U32.shln(major, 22n), U32.or(U32.shln(minor, 12n), patch)))

def api_version_major(version: U32) -> U32:
  U32.and(U32.shrn(version, 22n), 127)

def api_version_minor(version: U32) -> U32:
  U32.and(U32.shrn(version, 12n), 1023)

def api_version_patch(version: U32) -> U32:
  U32.and(version, 4095)

def flags_contains(+flags: U32, +required: U32) -> Bool:
  U32.is_eq(U32.and(flags, required), required)

type MemoryType is Data:
  MemoryType{property_flags: U32, heap_index: U32}

def memory_type_go(types: List<MemoryType>, +bits: U32, +required: U32, +index: U32) -> Maybe<U32>:
  match types:
    case Nil{}:
      None{}
    case Con{MemoryType{flags, heap}, rest}:
      Bool.pick(Maybe<U32>,
        Bool.and(U32.is_ne(U32.and(bits, 1), 0), flags_contains(flags, required)),
        Some{index}, memory_type_go(rest, U32.shr(bits), required, U32.inc(index)))

def find_memory_type(types: List<MemoryType>, bits: U32, required: U32) -> Maybe<U32>:
  memory_type_go(types, bits, required, 0)

def queue_go(families: List<(U32 & U32)>, +required: U32, +index: U32) -> Maybe<U32>:
  match families:
    case Nil{}:
      None{}
    case Con{(flags, count), rest}:
      Bool.pick(Maybe<U32>,
        Bool.and(U32.is_ne(count, 0), flags_contains(flags, required)),
        Some{index}, queue_go(rest, required, U32.inc(index)))

def find_queue_family(families: List<(U32 & U32)>, required: U32) -> Maybe<U32>:
  queue_go(families, required, 0)

# Packed uploads emit the low-order byte first.
def word_byte(word: U32, byte_index: U32) -> U32:
  U32.and(U32.shrn(word, U32.to_nat(U32.mul(8, U32.and(byte_index, 3)))), 255)

def size_less(a: W.U64, b: W.U64) -> Bool:
  W.U64{alo,+ahi} = a
  W.U64{blo,+bhi} = b
  Bool.or(U32.is_lt(ahi,bhi),Bool.and(U32.is_eq(ahi,bhi),U32.is_lt(alo,blo)))

def size_add_checked(+a: W.U64, b: W.U64) -> Maybe<W.U64>:
  +sum : W.U64 = W.add(a,b)
  Bool.pick(Maybe<W.U64>,size_less(sum,a),None{},Some{sum})

def size_scale_go(remaining: Nat, +value: W.U64, +factor: U32, +overflow: Bool, accumulator: W.U64) -> Maybe<W.U64>:
  match remaining:
    case 0n:
      Some{accumulator}
    case 1n+rest:
      +bit : Bool = U32.is_ne(U32.and(factor,1),0)
      +doubled : W.U64 = W.add(value,value)
      do Maybe<W.U64>:
        sum : W.U64 <- Bool.pick(Maybe<W.U64>,Bool.and(bit,overflow),None{},size_add_checked(accumulator,Bool.pick(W.U64,bit,value,W.zero())))
        size_scale_go(rest,doubled,U32.shr(factor),Bool.or(overflow,size_less(doubled,value)),sum)

def size_scale_checked(value: W.U64, factor: U32) -> Maybe<W.U64>:
  size_scale_go(32n,value,factor,False{},W.zero())

def image_mip_dimension(+base: U32, +level: U32) -> U32:
  +size : U32 = U32.shrn(base,U32.to_nat(U32.and(level,31)))
  Bool.pick(U32,Bool.or(U32.is_ge(level,32),U32.is_zero(size)),1,size)

def image_range_contains(+limit: U32, +base: U32, +count: U32) -> Bool:
  Bool.and(U32.is_ne(count,0),Bool.and(U32.is_lt(base,limit),U32.is_le(count,U32.sub(limit,base))))

def image_copy_end(offset: W.U64, +row_length: U32, +image_height: U32, +width: U32, +height: U32, +layers: U32, +element_bytes: U32) -> Maybe<W.U64>:
  +row_texels : U32 = Bool.pick(U32,U32.is_zero(row_length),width,row_length)
  +rows : U32 = Bool.pick(U32,U32.is_zero(image_height),height,image_height)
  valid : Bool = Bool.and(Bool.and(U32.is_ne(width,0),U32.is_ne(height,0)),Bool.and(Bool.and(U32.is_ne(layers,0),U32.is_ne(element_bytes,0)),Bool.and(U32.is_ge(row_texels,width),U32.is_ge(rows,height))))
  do Maybe<W.U64>:
    guard : Unit <- Bool.pick(Maybe<Unit>,valid,Some{Unit{}},None{})
    +row : W.U64 <- size_scale_checked(W.of_u32(row_texels),element_bytes)
    layer : W.U64 <- size_scale_checked(row,rows)
    last_layer : W.U64 <- size_scale_checked(layer,U32.sub(layers,1))
    last_row : W.U64 <- size_scale_checked(row,U32.sub(height,1))
    payload : W.U64 <- size_scale_checked(W.of_u32(width),element_bytes)
    prefix : W.U64 <- size_add_checked(last_layer,last_row)
    span : W.U64 <- size_add_checked(prefix,payload)
    size_add_checked(offset,span)
