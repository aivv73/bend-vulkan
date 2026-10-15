import Base
import ./LAWS.bend as Laws
import ./src/core.bend as Core
import ./deps/bend-collections/src/math/u64.bend as W

def Laws.size_words_roundtrip(value):
  match value:
    case W.U64{lo, hi}:
      {==}

def Laws.whole_size_bits():
  {==}

def Laws.no_allowed_memory(types, required, index):
  match types:
    case Nil{}:
      {==}
    case Con{Core.MemoryType{flags, heap}, rest}:
      Laws.no_allowed_memory(rest, required, U32.inc(index))

def Laws.memory_filters_flags():
  {==}

def Laws.memory_filters_type_bits():
  {==}

def Laws.memory_uses_first_match():
  {==}

def Laws.queue_skips_empty():
  {==}

def Laws.queue_filters_flags():
  {==}

def Laws.version_1_0():
  {==}

def Laws.version_fields():
  {==}

def Laws.result_device_lost_bits():
  {==}

def Laws.packed_word_bytes():
  {==}

def Laws.packed_index_wraps():
  {==}

def Laws.image_copy_last_byte():
  {==}
def Laws.image_copy_readback_last_byte():
  {==}
def Laws.image_copy_tight_padding():
  {==}
def Laws.image_copy_overflow():
  {==}
def Laws.image_copy_product_overflow():
  {==}
def Laws.size_checked_wrap():
  {==}
def Laws.image_mip_floor():
  {==}
def Laws.image_range_no_wrap():
  {==}
