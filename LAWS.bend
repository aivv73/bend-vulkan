import Base
import ./src/core.bend as Core
import ./src/constants.bend as vk
import ./deps/bend-collections/src/math/u64.bend as W
import ./examples/voxel/mesh.bend as Mesh
import ./examples/voxel/geometry.bend as Geometry
import ./deps/bend-voxel/voxel.bend as Voxel
import ./deps/bend-voxel/render.bend as Reference

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

law binding_alignment_includes_memory:
  {Core.binding_aligned(W.of_u32(2),W.of_u32(8),4) == False{} : Bool}
law binding_alignment_compensates:
  {Core.binding_aligned(W.of_u32(2),W.of_u32(10),4) == True{} : Bool}
law binding_alignment_high_limbs:
  {Core.binding_aligned(W.U64{2,4294967295},W.U64{10,4294967295},4) == True{} : Bool}
law binding_alignment_rejects_width:
  {Core.binding_aligned(W.zero(),W.zero(),3) == False{} : Bool}


law voxel_full_material_word:
  for material: U32
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},0,0,material,0,[0 : U32^5n])) == material : U32}

law voxel_high_material_bits:
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},5,0,4294967295,0,[0 : U32^5n])) == 4294967295 : U32}

law voxel_rgb_direction_bytes:
  {Mesh.rgbd(1193046,5) == 89535506 : U32}

law voxel_all_direction_codes:
  {[Mesh.direction(Voxel.NegX{}),Mesh.direction(Voxel.PosX{}),Mesh.direction(Voxel.NegY{}),Mesh.direction(Voxel.PosY{}),Mesh.direction(Voxel.NegZ{}),Mesh.direction(Voxel.PosZ{})] == [0,1,2,3,4,5] : List<U32>}

law voxel_empty_face_count:
  {Mesh.count(Nil{}) == 0 : U32}

law voxel_face_count_step:
  for face: Voxel.Face
  for faces: List<&2,Voxel.Face>
  {Mesh.count(face <> faces) == U32.add(1,Mesh.count(faces)) : U32}

law voxel_quad_index_pattern:
  for base: U32
  {Array.to_list(~U32,Mesh.index_quad(base,0,[0 : U32^3n])) == [base,U32.add(base,1),U32.add(base,2),U32.add(base,2),U32.add(base,3),base,0,0] : List<U32>}

law voxel_intact_counts:
  {((384 * 4 : U32),(384 * 6 : U32),(384 * 80 : U32),(384 * 24 : U32)) == (1536,2304,30720,9216) : U32 & U32 & U32 & U32}

law voxel_max_fixture_index:
  {Array.to_list(~U32,Mesh.index_quad(12284,0,[0 : U32^3n])) == [12284,12285,12286,12286,12287,12284,0,0] : List<U32>}

law voxel_quad_outward:
  {[Geometry.quad_normal(0),Geometry.quad_normal(1),Geometry.quad_normal(2),Geometry.quad_normal(3),Geometry.quad_normal(4),Geometry.quad_normal(5)] == [Voxel.Cell{4294967295,0,0},Voxel.Cell{1,0,0},Voxel.Cell{0,4294967295,0},Voxel.Cell{0,1,0},Voxel.Cell{0,0,4294967295},Voxel.Cell{0,0,1}] : List<Voxel.Cell>}

law voxel_second_triangle_outward:
  {[Geometry.quad_second_normal(0),Geometry.quad_second_normal(1),Geometry.quad_second_normal(2),Geometry.quad_second_normal(3),Geometry.quad_second_normal(4),Geometry.quad_second_normal(5)] == [Voxel.Cell{4294967295,0,0},Voxel.Cell{1,0,0},Voxel.Cell{0,4294967295,0},Voxel.Cell{0,1,0},Voxel.Cell{0,0,4294967295},Voxel.Cell{0,0,1}] : List<Voxel.Cell>}

law voxel_all_8cube_indices_bounded:
  {Geometry.fixture_index_bounds(3072n,0) == True{} : Bool}

law presentation_common_queue:
  {Core.queue_pair([Core.QueueSupport{1,1,True{}},Core.QueueSupport{4,1,True{}}],False{}) == Some{Core.QueuePair{0,0}} : Maybe<Core.QueuePair>}

law presentation_split_queue:
  {Core.queue_pair([Core.QueueSupport{1,1,False{}},Core.QueueSupport{4,1,True{}}],False{}) == Some{Core.QueuePair{0,1}} : Maybe<Core.QueuePair>}

law presentation_forced_split_queue:
  {Core.queue_pair([Core.QueueSupport{1,1,True{}},Core.QueueSupport{4,1,True{}}],True{}) == Some{Core.QueuePair{0,1}} : Maybe<Core.QueuePair>}

law presentation_empty_queue_rejected:
  {Core.queue_pair([Core.QueueSupport{1,0,True{}}],False{}) == None{} : Maybe<Core.QueuePair>}

law presentation_image_count:
  {(Core.present_image_count(2,0),Core.present_image_count(2,2),Core.present_image_count(2,4)) == (3,2,3) : U32 & U32 & U32}

law presentation_suspend_before_clamp:
  for mapped: Bool
  {Core.drawable(mapped,0,720) == False{} : Bool}

law presentation_variable_extent:
  {Core.surface_extent(4294967295,4294967295,16,16,1024,1024,800,450) == (800,450) : U32 & U32}

law presentation_fixed_extent:
  {Core.surface_extent(450,700,16,16,1024,1024,800,450) == (450,700) : U32 & U32}

law presentation_landscape_pixel_center:
  {Core.viewport_pixel_units(800,450,399,224) == (4294967295,1) : U32 & U32}

law presentation_portrait_pixel_center:
  {Core.viewport_pixel_units(450,700,225,350) == (1,4294967295) : U32 & U32}

law presentation_undefined_format:
  {Core.surface_format([(0,17)]) == Some{(44,17)} : Maybe<(U32 & U32)>}

law presentation_preserves_color_space:
  {Core.surface_format([(7,0),(44,1000104001)]) == Some{(44,1000104001)} : Maybe<(U32 & U32)>}

law presentation_fifo_required:
  {(Core.fifo_supported([0,1]),Core.fifo_supported([0,2])) == (False{},True{}) : Bool & Bool}

law presentation_prefers_unorm:
  {Core.surface_format([(50,0),(44,0)]) == Some{(44,0)} : Maybe<(U32 & U32)>}

law presentation_undefined_requires_single_format:
  {Core.surface_format([(37,0),(0,17)]) == Some{(37,0)} : Maybe<(U32 & U32)>}

law descriptor_empty_schema:
  {Core.descriptor_schema(~U32,~(x => x),[]) == [] : List<U32>}

law descriptor_insert_single:
  for binding: U32
  {Core.descriptor_insert(~U32,~(x => x),[],binding) == [binding] : List<U32>}

law descriptor_sparse_canonical:
  {Core.descriptor_schema(~U32,~(x => x),[9,3,0]) == [0,3,9] : List<U32>}
