import Base
import ./src/core.bend as Core
import ./src/constants.bend as vk
import ./deps/bend-collections/src/math/u64.bend as W

# Native marshalling must preserve these limbs; the C boundary is tested separately.
law size_words_roundtrip:
  for value: W.U64
  {Core.size_from_words(Core.size_words(value)) == value : W.U64}

law whole_size_bits:
  {Core.whole_size() == W.U64{4294967295, 4294967295} : W.U64}

law no_allowed_memory:
  for types: List<Core.MemoryType>
  for required: U32
  for index: U32
  {Core.memory_type_go(types, 0, required, index) == None{} : Maybe<U32>}

law memory_filters_flags:
  {Core.find_memory_type([Core.MemoryType{1, 0}, Core.MemoryType{6, 0}], 3, 6) == Some{1} : Maybe<U32>}

law memory_filters_type_bits:
  {Core.find_memory_type([Core.MemoryType{6, 0}, Core.MemoryType{6, 0}], 2, 6) == Some{1} : Maybe<U32>}

law memory_uses_first_match:
  {Core.find_memory_type([Core.MemoryType{6, 0}, Core.MemoryType{6, 0}], 3, 6) == Some{0} : Maybe<U32>}

law queue_skips_empty:
  {Core.find_queue_family([(3, 0), (1, 1)], 1) == Some{1} : Maybe<U32>}

law queue_filters_flags:
  {Core.find_queue_family([(2, 1), (1, 1)], 1) == Some{1} : Maybe<U32>}

law version_1_0:
  {Core.make_api_version(0, 1, 0, 0) == 4194304 : U32}

law version_fields:
  {(Core.api_version_major(536887305), (Core.api_version_minor(536887305), Core.api_version_patch(536887305))) == (0, (4, 9)) : U32 & (U32 & U32)}

law result_device_lost_bits:
  {vk.VK_ERROR_DEVICE_LOST() == 4294967292 : U32}

law packed_word_bytes:
  {(Core.word_byte(16909060, 0), (Core.word_byte(16909060, 1), (Core.word_byte(16909060, 2), Core.word_byte(16909060, 3)))) == (4, (3, (2, 1))) : U32 & (U32 & (U32 & U32))}

law packed_index_wraps:
  {Core.word_byte(16909060, 4) == 4 : U32}

law image_copy_last_byte:
  {Core.image_copy_end(W.of_u32(12),7,5,3,2,2,4) == Some{W.of_u32(192)} : Maybe<W.U64>}

law image_copy_readback_last_byte:
  {Core.image_copy_end(W.of_u32(20),9,6,3,2,2,4) == Some{W.of_u32(284)} : Maybe<W.U64>}

law image_copy_tight_padding:
  {Core.image_copy_end(W.of_u32(8),0,0,3,2,2,4) == Core.image_copy_end(W.of_u32(8),3,2,3,2,2,4) : Maybe<W.U64>}

law image_copy_overflow:
  {Core.image_copy_end(Core.whole_size(),0,0,1,1,1,4) == None{} : Maybe<W.U64>}

law image_copy_product_overflow:
  {Core.image_copy_end(W.zero(),4294967295,4294967295,1,1,4294967295,4) == None{} : Maybe<W.U64>}

law size_checked_wrap:
  {Core.size_add_checked(Core.whole_size(),W.of_u32(1)) == None{} : Maybe<W.U64>}

law image_mip_floor:
  {(Core.image_mip_dimension(9,1),Core.image_mip_dimension(9,32)) == (4,1) : U32 & U32}

law image_range_no_wrap:
  {Core.image_range_contains(5,4294967295,2) == False{} : Bool}

law size_limbs_roundtrip:
  for words: U32 & U32
  {Core.size_words(Core.size_from_words(words)) == words : U32 & U32}

law size_scale_zero:
  {Core.size_scale_checked(Core.whole_size(),0) == Some{W.zero()} : Maybe<W.U64>}

law index_span_u16:
  {Core.index_span_end(W.of_u32(6),3,6,2) == Some{W.of_u32(24)} : Maybe<W.U64>}
law index_span_widens:
  {Core.index_span_end(W.zero(),4294967295,2,4) == Some{W.U64{4,4}} : Maybe<W.U64>}
law index_span_rejects_width:
  {Core.index_span_end(W.zero(),0,1,3) == None{} : Maybe<W.U64>}
law index_span_overflow:
  {Core.index_span_end(Core.whole_size(),0,1,2) == None{} : Maybe<W.U64>}
