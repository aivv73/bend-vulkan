import Base
import ./examples/voxel/exterior.bend as Exterior
import ./examples/voxel/geometry-laws.bend as GeometryLaws
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
def Laws.voxel_face_count_step(face,faces,n):
  {==}
def Laws.voxel_face_count_limit(face):
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

def Laws.exterior_subtract_center_four_disjoint_pieces():
  {==}

def Laws.exterior_subtract_touching_unchanged():
  {==}

def Laws.exterior_subtract_contains_empty():
  {==}

def Laws.exterior_rectangle_preserves_full_material(normal,d,m,r):
  match r:
    case Exterior.Rect2{u0,u1,v0,v1}:
      {==}

def Laws.exterior_rectangle_preserves_direction(normal,d,m,r):
  match r:
    case Exterior.Rect2{u0,u1,v0,v1}:
      {==}

def Laws.exterior_indices_preserve_order(base):
  {==}

def Laws.exterior_coordinate_bound_exact():
  {==}

def Laws.exterior_coordinate_bound_rejects_next():
  {==}

def Laws.exterior_count_limit_accepts_exact():
  {==}

def Laws.exterior_count_limit_rejects_next():
  {==}

def Laws.exterior_count_limit_rejects_wrapping_product():
  {==}

def Laws.exterior_capacity_bytes_keep_high_limb():
  {==}

def Laws.exterior_asymmetric_first_normals():
  {==}

def Laws.exterior_asymmetric_second_normals():
  {==}

def Laws.exterior_overlap_rejected_with_sources():
  {==}
def Laws.exterior_clipping_preserves_every_material(rs,normal,d,m,old):
  match rs:
    case Nil{}: {==}
    case Exterior.Rect2{a,b,c,e} <> rest:
      %Laws.exterior_clipping_preserves_every_material(rest,normal,d,m,old) : {m <> GeometryLaws.materials(Exterior.lift(rest,Exterior.Patch{normal,d,m,old})) == m <> _ : List<U32>}
      {==}


def Laws.appearance_payload_bytes():
  {==}

def Laws.appearance_payload_words():
  {==}

def Laws.appearance_selected_offset():
  {==}

def Laws.appearance_ring_index_count():
  {==}


def Laws.upload_source_range_exact_end():
  {==}

def Laws.upload_source_range_rejects_next():
  {==}

def Laws.upload_source_range_no_wrap():
  {==}

def Laws.upload_empty_at_end():
  {==}


def Laws.chunk_region_boundary():
  {==}

def Laws.chunk_huge_source_stays_analytic():
  {==}

def Laws.chunk_dirty_neighbor_boundary():
  {==}

def Laws.chunk_low_boundary_clamped():
  {==}

def Laws.chunk_full_source_tuple_required():
  {==}

def Laws.greedy_exact_shared_edge():
  {==}

def Laws.greedy_material_boundary():
  {==}

def Laws.greedy_plane_boundary():
  {==}

def Laws.greedy_gap_rejected():
  {==}

def Laws.greedy_four_tiles_one_rectangle():
  {==}

def Laws.chunk_runs_merge_only_adjacent_local_ranges():
  {==}

def Laws.retirement_keeps_exact_key_and_version():
  {==}

def Laws.retirement_selects_changed_and_removed():
  {==}

def Laws.retirement_equal_version_different_key_is_obsolete():
  {==}

def Laws.retirement_empty_has_no_allocations():
  {==}
