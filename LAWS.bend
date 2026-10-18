import Base
import ./examples/voxel/chunks.bend as Chunks
import ./examples/voxel/greedy.bend as Greedy
import ./examples/voxel/appearance.bend as Appearance
import ./shaders/appearance_uniforms.bend as Uniform
import ./examples/voxel/geometry-laws.bend as GeometryLaws
import ./src/core.bend as Core
import ./src/constants.bend as vk
import ./deps/bend-collections/src/math/u64.bend as W
import ./examples/voxel/mesh.bend as Mesh
import ./examples/voxel/geometry.bend as Geometry
import ./examples/voxel/exterior.bend as Exterior
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
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},0,0,material,1,1,0,[0 : U32^6n])) == material : U32}

law voxel_high_material_bits:
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},5,0,4294967295,1,1,0,[0 : U32^6n])) == 4294967295 : U32}

law voxel_rgb_direction_bytes:
  {Mesh.rgbd(1193046,5) == 89535506 : U32}

law voxel_all_direction_codes:
  {[Exterior.direction(Voxel.NegX{}),Exterior.direction(Voxel.PosX{}),Exterior.direction(Voxel.NegY{}),Exterior.direction(Voxel.PosY{}),Exterior.direction(Voxel.NegZ{}),Exterior.direction(Voxel.PosZ{})] == [0,1,2,3,4,5] : List<U32>}

law voxel_empty_face_count:
  {Exterior.count(Nil{},0) == Done{0} : Result<&2,&2,Exterior.Error,U32>}

law voxel_face_count_step:
  for face: Voxel.Face
  for faces: List<&2,Voxel.Face>
  for n: U32
  {Exterior.count(face <> faces,n) == GeometryLaws.bounded_count_step(faces,n) : Result<&2,&2,Exterior.Error,U32>}

law voxel_face_count_limit:
  for face: Voxel.Face
  {Exterior.count([face],26843545) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,U32>}

law voxel_quad_index_pattern:
  for base: U32
  {Array.to_list(~U32,Mesh.index_quad(base,0,[0 : U32^3n])) == [base,U32.add(base,1),U32.add(base,2),U32.add(base,2),U32.add(base,3),base,0,0] : List<U32>}

law voxel_intact_counts:
  {((384 * 4 : U32),(384 * 6 : U32),(384 * 160 : U32),(384 * 24 : U32)) == (1536,2304,61440,9216) : U32 & U32 & U32 & U32}

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

law exterior_subtract_center_four_disjoint_pieces:
  {Exterior.subtract(Exterior.Rect2{0,7,0,9},Exterior.Rect2{2,5,3,6}) == [Exterior.Rect2{0,2,0,9},Exterior.Rect2{5,7,0,9},Exterior.Rect2{2,5,0,3},Exterior.Rect2{2,5,6,9}] : List<&2,Exterior.Rect2>}

law exterior_subtract_touching_unchanged:
  {Exterior.subtract(Exterior.Rect2{1,4,2,7},Exterior.Rect2{4,8,3,5}) == [Exterior.Rect2{1,4,2,7}] : List<&2,Exterior.Rect2>}

law exterior_subtract_contains_empty:
  {Exterior.subtract(Exterior.Rect2{1,4,2,7},Exterior.Rect2{0,5,0,8}) == Nil{} : List<&2,Exterior.Rect2>}

law exterior_rectangle_preserves_full_material:
  for normal: U32
  for d: Voxel.Direction
  for m: U32
  for r: Exterior.Rect2
  {GeometryLaws.material(Exterior.face(normal,d,m,r)) == m : U32}

law exterior_rectangle_preserves_direction:
  for normal: U32
  for +d: Voxel.Direction
  for m: U32
  for r: Exterior.Rect2
  {GeometryLaws.face_direction(Exterior.face(normal,d,m,r)) == d : Voxel.Direction}

law exterior_indices_preserve_order:
  for +base: U32
  {Array.to_list(~U32,Mesh.index_quad(base,0,[0 : U32^3n])) == [base,(base + 1 : U32),(base + 2 : U32),(base + 2 : U32),(base + 3 : U32),base,0,0] : List<U32>}

law exterior_coordinate_bound_exact:
  {Exterior.box_bounded(Voxel.Cuboid{Voxel.Cell{1048575,0,0},Voxel.Cell{1048576,1,1},4294967295}) == True{} : Bool}

law exterior_coordinate_bound_rejects_next:
  {Exterior.box_bounded(Voxel.Cuboid{Voxel.Cell{1048576,0,0},Voxel.Cell{1048577,1,1},1}) == False{} : Bool}

law exterior_count_limit_accepts_exact:
  {Result.is_done(&2,&2,Exterior.Error,Mesh.PackedSize,Mesh.size(26843545)) == True{} : Bool}

law exterior_count_limit_rejects_next:
  {Mesh.size(26843546) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,Mesh.PackedSize>}

law exterior_count_limit_rejects_wrapping_product:
  {Mesh.size(4294967295) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,Mesh.PackedSize>}

law exterior_capacity_bytes_keep_high_limb:
  {Mesh.word_bytes(1073741824) == W.U64{0,1} : W.U64}

law exterior_asymmetric_first_normals:
  {[GeometryLaws.first(0),GeometryLaws.first(1),GeometryLaws.first(2),GeometryLaws.first(3),GeometryLaws.first(4),GeometryLaws.first(5)] == [Voxel.Cell{4294967290,0,0},Voxel.Cell{6,0,0},Voxel.Cell{0,4294967290,0},Voxel.Cell{0,6,0},Voxel.Cell{0,0,4294967290},Voxel.Cell{0,0,6}] : List<&2,Voxel.Cell>}

law exterior_asymmetric_second_normals:
  {[GeometryLaws.second(0),GeometryLaws.second(1),GeometryLaws.second(2),GeometryLaws.second(3),GeometryLaws.second(4),GeometryLaws.second(5)] == [Voxel.Cell{4294967290,0,0},Voxel.Cell{6,0,0},Voxel.Cell{0,4294967290,0},Voxel.Cell{0,6,0},Voxel.Cell{0,0,4294967290},Voxel.Cell{0,0,6}] : List<&2,Voxel.Cell>}

law exterior_overlap_rejected_with_sources:
  {Exterior.validate([Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{3,3,3},1},Voxel.Cuboid{Voxel.Cell{1,1,1},Voxel.Cell{2,2,2},2}],0) == Fail{Exterior.OverlappingBoxes{0,1}} : Result<&2,&2,Exterior.Error,Unit>}

law exterior_clipping_preserves_every_material:
  for rs: List<&2,Exterior.Rect2>
  for +normal: U32
  for +d: Voxel.Direction
  for +m: U32
  for +old: Exterior.Rect2
  {GeometryLaws.materials(Exterior.lift(rs,Exterior.Patch{normal,d,m,old})) == GeometryLaws.repeated(rs,m) : List<U32>}


law appearance_payload_bytes:
  {Uniform.byte_size() == 2336 : U32}

law appearance_payload_words:
  {Uniform.word_count() == 584 : U32}

law appearance_selected_offset:
  {Uniform.offset_selected() == 336 : U32}

law appearance_ring_index_count:
  {Appearance.ring_index_count() == 576 : U32}

law chunk_region_boundary:
  {[Chunks.region(32,Voxel.Cell{31,32,63}),Chunks.region(32,Voxel.Cell{32,31,64})] == [Chunks.ChunkKey{0,32,32,32},Chunks.ChunkKey{32,0,64,32}] : List<&2,Chunks.ChunkKey>}

law chunk_huge_source_stays_analytic:
  {Chunks.source_key(Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{1048576,1048576,1048576},1}) == Chunks.ChunkKey{0,0,0,1048576} : Chunks.ChunkKey}

law chunk_dirty_neighbor_boundary:
  {Chunks.dependency_region(Chunks.ChunkKey{32,0,0,32},64) == Voxel.Cuboid{Voxel.Cell{31,0,0},Voxel.Cell{64,33,33},1} : Voxel.Cuboid}

law chunk_low_boundary_clamped:
  {Chunks.dependency_region(Chunks.ChunkKey{0,0,0,32},64) == Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{33,33,33},1} : Voxel.Cuboid}

law chunk_full_source_tuple_required:
  {Chunks.box_equal(Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{4,4,4},1},Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{4,4,4},4294967295}) == False{} : Bool}

law greedy_exact_shared_edge:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == Some{Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{0,8,2,6}}} : Maybe<&2,Exterior.Patch>}

law greedy_material_boundary:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_plane_boundary:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{8,Voxel.PosZ{},1,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_gap_rejected:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{4,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_four_tiles_one_rectangle:
  {Greedy.merge_faces([Voxel.Rectangle{Voxel.Cell{0,0,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{2,0,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{0,3,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{2,3,7},Voxel.PosZ{},1,2,3}]) == [Voxel.Rectangle{Voxel.Cell{0,0,7},Voxel.PosZ{},1,4,6}] : List<&2,Voxel.Face>}


law chunk_runs_merge_only_adjacent_local_ranges:
  {Chunks.runs([Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},0,Voxel.Face{Voxel.Cell{0,0,0},Voxel.NegX{},1}},Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},1,Voxel.Face{Voxel.Cell{0,0,0},Voxel.PosX{},1}},Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},3,Voxel.Face{Voxel.Cell{0,0,0},Voxel.NegY{},1}}]) == [Chunks.Run{Chunks.ChunkKey{0,0,0,32},0,2},Chunks.Run{Chunks.ChunkKey{0,0,0,32},3,1}] : List<&2,Chunks.Run>}
