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

def Laws.voxel_intact_counts():
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

def Laws.upload_source_range_exact_end():
  {==}

def Laws.upload_source_range_rejects_next():
  {==}

def Laws.upload_source_range_no_wrap():
  {==}

def Laws.upload_empty_at_end():
  {==}


def Laws.completed_revision_first_zero():
  {==}

def Laws.completed_revision_reverse_order():
  {==}

def Laws.completed_revision_unavailable_ignored():
  {==}

def Laws.revision_last_valid():
  {==}

def Laws.revision_exhaustion_does_not_wrap():
  {==}

def Laws.submission_sequence_blocks_newer():
  {==}

def Laws.submission_sequence_accepts_exact():
  {==}

def Laws.submission_sequence_checks_high_limb():
  {==}

def Laws.submission_sequence_carries():
  {==}

def Laws.submission_sequence_never_wraps():
  {==}
