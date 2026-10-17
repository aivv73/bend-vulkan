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

def index_span_end(offset: W.U64, +first: U32, count: U32, +width: U32) -> Maybe<W.U64>:
  do Maybe<W.U64>:
    valid : Unit <- Bool.pick(Maybe<Unit>,Bool.or(U32.is_eq(width,2),U32.is_eq(width,4)),Some{Unit{}},None{})
    elements : W.U64 <- size_add_checked(W.of_u32(first),W.of_u32(count))
    bytes : W.U64 <- size_scale_checked(elements,width)
    size_add_checked(offset,bytes)

def alignment_parts(+binding_lo: U32, +relative_lo: U32, width: U32) -> Bool:
  match width:
    case 1:
      True{}
    case 2:
      U32.is_zero(U32.and(U32.add(U32.and(binding_lo,1),U32.and(relative_lo,1)),1))
    case 4:
      U32.is_zero(U32.and(U32.add(U32.and(binding_lo,3),U32.and(relative_lo,3)),3))
    case _:
      False{}

def binding_aligned(binding: W.U64, relative: W.U64, width: U32) -> Bool:
  W.U64{binding_lo,binding_hi} = binding
  W.U64{relative_lo,relative_hi} = relative
  alignment_parts(binding_lo,relative_lo,width)

type QueueSupport is Data:
  QueueSupport{flags: U32, count: U32, present: Bool}
type QueuePair is Data:
  QueuePair{graphics: U32, present: U32}

def present_queue(xs: List<&2,QueueSupport>, +index: U32, +skip: Maybe<&2,U32>) -> Maybe<U32>:
  match xs skip:
    case Nil{} _: None{}
    case Con{QueueSupport{flags,count,present},rest} None{}:
      Bool.pick(Maybe<U32>,present && U32.is_ne(count,0),Some{index},present_queue(rest,U32.inc(index),None{}))
    case Con{QueueSupport{flags,count,present},rest} Some{ignored}:
      Bool.pick(Maybe<U32>,present && U32.is_ne(count,0) && U32.is_ne(index,ignored),Some{index},present_queue(rest,U32.inc(index),Some{ignored}))

def graphics_queue(xs: List<&2,QueueSupport>, +index: U32, +common: Bool) -> Maybe<U32>:
  match xs:
    case Nil{}: None{}
    case Con{QueueSupport{flags,count,present},rest}:
      Bool.pick(Maybe<U32>,flags_contains(flags,1) && U32.is_ne(count,0) && (Bool.not(common) || present),Some{index},graphics_queue(rest,U32.inc(index),common))

def queue_pair_selected(graphics: Maybe<U32>, present: Maybe<U32>) -> Maybe<QueuePair>:
  do Maybe<QueuePair>:
    g : U32 <- graphics
    p : U32 <- present
    return QueuePair{g,p}

def queue_pair_split(+xs: List<&2,QueueSupport>, selected: Maybe<U32>, split: Bool) -> Maybe<QueuePair>:
  match selected split:
    case None{} _: queue_pair_selected(graphics_queue(xs,0,False{}),present_queue(xs,0,None{}))
    case Some{+g} False{}: Some{QueuePair{g,g}}
    case Some{+g} True{}: queue_pair_selected(Some{g},present_queue(xs,0,Some{g}))

def queue_pair(+xs: List<&2,QueueSupport>, split: Bool) -> Maybe<QueuePair>:
  queue_pair_split(xs,graphics_queue(xs,0,True{}),split)

def present_image_count(+minimum: U32, +maximum: U32) -> U32:
  +wanted = Bool.pick(U32,U32.is_eq(minimum,4294967295),minimum,U32.inc(minimum))
  Bool.pick(U32,U32.is_zero(maximum),wanted,U32.min(wanted,maximum))

def drawable(mapped: Bool, +width: U32, +height: U32) -> Bool:
  mapped && U32.is_ne(width,0) && U32.is_ne(height,0)

def surface_extent(+current_width: U32, +current_height: U32, +min_width: U32, +min_height: U32, +max_width: U32, +max_height: U32, width: U32, height: U32) -> U32 & U32:
  (Bool.pick(U32,U32.is_eq(current_width,4294967295),U32.max(min_width,U32.min(width,max_width)),current_width),Bool.pick(U32,U32.is_eq(current_height,4294967295),U32.max(min_height,U32.min(height,max_height)),current_height))

def viewport_pixel_units(width: U32, height: U32, x: U32, y: U32) -> U32 & U32:
  ((x * 2 + 1 - width : U32),(height - y * 2 - 1 : U32))

def signed_half(+value: U32) -> F32:
  Bool.pick(F32,U32.is_gt(value,2147483647),F32.neg((U32.to_f32((0 - value : U32)) * 0.5 : F32)),(U32.to_f32(value) * 0.5 : F32))

def viewport_pixel_halves(units: U32 & U32) -> F32 & F32:
  (x,y) = units
  (signed_half(x),signed_half(y))

def viewport_pixel(width: U32, height: U32, x: U32, y: U32) -> F32 & F32:
  viewport_pixel_halves(viewport_pixel_units(width,height,x,y))

def surface_format_rank(format: U32) -> U32:
  match format:
    case 44: 0
    case 37: 1
    case 50: 2
    case 43: 3
    case _: 4

def surface_prefer(+format: U32, +space: U32, next: Maybe<(U32 & U32)>) -> Maybe<(U32 & U32)>:
  match next:
    case None{}: Bool.pick(Maybe<(U32 & U32)>,U32.is_lt(surface_format_rank(format),4),Some{(format,space)},None{})
    case Some{(+other,+color_space)}:
      Bool.pick(Maybe<(U32 & U32)>,U32.is_le(surface_format_rank(format),surface_format_rank(other)),Some{(format,space)},Some{(other,color_space)})

def surface_formats_go(formats: List<(U32 & U32)>) -> Maybe<(U32 & U32)>:
  match formats:
    case Nil{}: None{}
    case Con{(format,space),rest}: surface_prefer(format,space,surface_formats_go(rest))

def surface_format(formats: List<(U32 & U32)>) -> Maybe<(U32 & U32)>:
  match formats:
    case Nil{}: None{}
    case Con{(0,space),Nil{}}: Some{(44,space)}
    case Con{(format,space),rest}: surface_prefer(format,space,surface_formats_go(rest))

def fifo_supported(modes: List<U32>) -> Bool:
  match modes:
    case Nil{}: False{}
    case Con{mode,rest}: U32.is_eq(mode,2) || fifo_supported(rest)

def descriptor_order(~A: Data, ordered: Bool, value: A, head: A, next: A -> List<A>) -> List<A>:
  match ordered:
    case True{}: value <> next(head)
    case False{}: head <> next(value)

def descriptor_insert(~A: Data, ~number: A -> U32, bindings: List<A>, +value: A) -> List<A>:
  match bindings:
    case Nil{}: [value]
    case Con{+head,rest}:
      descriptor_order(~A,U32.is_le(number(value),number(head)),value,head,high => descriptor_insert(~A,~number,rest,high))

def descriptor_schema(~A: Data, ~number: A -> U32, bindings: List<A>) -> List<A>:
  match bindings:
    case Nil{}: []
    case Con{binding,rest}: descriptor_insert(~A,~number,descriptor_schema(~A,~number,rest),binding)
