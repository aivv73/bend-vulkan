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
