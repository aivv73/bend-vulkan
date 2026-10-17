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

def Laws.size_limbs_roundtrip(words):
  (lo,hi) = words
  {==}
def Laws.size_scale_zero():
  {==}

def Laws.index_span_u16():
  {==}
def Laws.index_span_widens():
  {==}
def Laws.index_span_rejects_width():
  {==}
def Laws.index_span_overflow():
  {==}

def Laws.binding_alignment_includes_memory():
  {==}
def Laws.binding_alignment_compensates():
  {==}
def Laws.binding_alignment_high_limbs():
  {==}
def Laws.binding_alignment_rejects_width():
  {==}

def Laws.voxel_full_material_word(material):
  {==}
def Laws.voxel_high_material_bits():
  {==}
def Laws.voxel_rgb_direction_bytes():
  {==}
def Laws.voxel_all_direction_codes():
  {==}
def Laws.voxel_empty_face_count():
  {==}
def Laws.voxel_face_count_step(face,faces):
  {==}
def Laws.voxel_quad_index_pattern(base):
  {==}
def Laws.voxel_intact_counts():
  {==}
def Laws.voxel_max_fixture_index():
  {==}
def Laws.voxel_quad_outward():
  {==}

def Laws.voxel_second_triangle_outward():
  {==}

def Laws.voxel_all_8cube_indices_bounded():
  {==}

def Laws.presentation_common_queue():
  {==}

def Laws.presentation_split_queue():
  {==}

def Laws.presentation_forced_split_queue():
  {==}

def Laws.presentation_empty_queue_rejected():
  {==}

def Laws.presentation_image_count():
  {==}

def Laws.presentation_suspend_before_clamp(mapped):
  match mapped:
    case False{}: {==}
    case True{}: {==}

def Laws.presentation_variable_extent():
  {==}

def Laws.presentation_fixed_extent():
  {==}

def Laws.presentation_landscape_pixel_center():
  {==}

def Laws.presentation_portrait_pixel_center():
  {==}

def Laws.presentation_undefined_format():
  {==}

def Laws.presentation_preserves_color_space():
  {==}

def Laws.presentation_fifo_required():
  {==}

def Laws.presentation_prefers_unorm():
  {==}

def Laws.presentation_undefined_requires_single_format():
  {==}

def Laws.descriptor_empty_schema():
  {==}

def Laws.descriptor_insert_single(binding):
  {==}

def Laws.descriptor_sparse_canonical():
  {==}
