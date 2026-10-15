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
