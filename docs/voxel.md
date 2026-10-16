# Offscreen voxel consumer

The consumer draws the dense 8³ body from the unmodified `bend-voxel` submodule at `cdfd92d356229c5de5f4aaddd358f15ec3686dd4`. Voxel types and geometry policy live in `examples/voxel/`. The Vulkan library has no voxel dependency.

The native readback below shows the intact cube on the left and the metric-demo carve on the right.

![Intact and carved Vulkan voxel readback](voxel-intact-carved.png)

## Run and inspect exports

Initialize dependencies, then build and run from the repository root with Bend 2.0.37:

```sh
git submodule update --init --recursive
mkdir -p build
bend examples/voxel_offscreen.bend -o build/voxel-offscreen
./build/voxel-offscreen
```

The executable writes 512 by 512 PPM images to `build/voxel-intact.ppm`, `build/voxel-carved.ppm`, `build/voxel-reset.ppm`, and `build/voxel-empty.ppm`. The main carve uses upstream `MetricSphere.demo()`, centered at 65 cm on each axis with a 20 cm radius. It removes cells by their center positions. This is distinct from upstream's geometry-dump sphere and screen-click carve.

`build/voxel-upstream-intact.ppm` and `build/voxel-upstream-carved.ppm` preserve the old renderer's shaded image, ground, and shadows for visual inspection. Its unchanged `Tiles.image` algorithm runs directly on the CPU. The Vulkan executable has zero Bend bang dispatches and requires no CUDA compiler, runtime, or `.gpu` artifact. Vulkan still requires a driver.

## Ownership and updates

`Mesh.build` returns `Body & Result<Error,Mesh>`. The returned Body equals the original input on success and failure. Body remains the edit authority. Mesh owns canonical `Face` or `Rectangle` coverage, checked logical counts and U64 byte lengths, optional half-open owning-cell bounds, and packed vertex and index arrays. Edit and startup boundaries report build errors explicitly.

Dense bodies retain pinned extraction semantics. Their side must be a positive power of two at most 1,024, with a balanced side-cubed array. Cuboids have positive half-open extents and endpoints at most 2^20. Nonair boxes must be disjoint. Overlap errors identify both source indices. Material zero contributes no occupancy and does not erase other boxes. Exterior extraction subtracts outside-adjacent nonair coverage from each source face. Its six pure face partitions run independently and retain source and direction order.

The checked source and quad limit is 26,843,545. Each padded array has at most 2^30 words. Counts are checked before products, allocation, or narrowing. The Bend runtime still owns allocation failure behavior. Before releasing old geometry or allocating buffers, the renderer checks both logical U64 byte lengths against the existing 16 MiB single-write limit. Padding is never uploaded. No chunked upload path is provided.

`Renderer.replace_mesh` releases the previous geometry and uploads the exact logical lengths of both new arrays. An empty mesh owns no vertex or index buffers. Calls occur after the previous synchronous frame has observed its fence and reset its command buffer. `Renderer.frame` accepts a camera and diagnostic mode. It records, submits, waits, reads RGBA8 and D32 staging bytes, and resets the command and fence. It neither meshes nor uploads geometry.

Mesh buffers use host-visible memory. A HOST_WRITE to VERTEX_INPUT barrier publishes their vertex and index contents. Images use explicit color/depth attachment and transfer-source transitions. The staging transfer is made visible to the host after fence completion. Scope cleanup uses the existing Vulkan resource graph. Replacements explicitly destroy buffers before freeing their allocations.

## Packed data

Every exposed unit face or rectangle has four vertices and six U32 indices. The triangle pattern is `0,1,2,2,3,0`, relative to the face's first vertex. Vertex stride is 40 bytes:

| Byte offset | Contents | Basic pipeline input format |
| --- | --- | --- |
| 0 | XYZ, three F32 words in voxel units | R32G32B32_SFLOAT |
| 12 | R, G, B, direction, one byte each | R8G8B8A8_UNORM |
| 16 | Complete material U32, little endian | R8G8B8A8_UNORM |
| 20 | Flat owning-cell anchor XYZ, three F32 words | Unused |
| 32 | Flat rectangle width and height, two F32 words | Unused |

Direction codes are `-X,+X,-Y,+Y,-Z,+Z` as `0,1,2,3,4,5`. The vertex shader recovers bytes with `round(attribute * 255)` and sends flat metadata to the fragment shader. The basic fragment shader outputs alpha one. The material diagnostic writes all four material bytes, including alpha. The direction diagnostic writes the direction byte to red and alpha one.

Basic colors come from upstream `material.Palette.surface` and `render.Face.light`, including the magenta fallback for unknown positive IDs. This byte encoding is display RGB in an RGBA8 UNORM target. No second sRGB conversion occurs. Mesh extraction and shader interpretation remain consumer responsibilities.

Binding offsets and base vertex are zero. Both triangles wind outward with cross-product area equal to width times height. The camera uses the upstream basis and pixel-center rays at 512 by 512. Camera-local XYZ maps to clip `(420/256*X, -420/256*Y, Z-near, Z)`. The positive-height viewport uses counterclockwise front faces and back-face culling. D32 depth is `1-near/Z`, with near 0.1 and an infinite far plane. Push constants are a 64-byte column-major matrix.

## Verification policy

`geometry.bend` independently enumerates cells and all six signed neighbors for small dense and cuboid fixtures. It compares oriented unit-face coverage, material, and multiplicity. It decodes packed positions, colors, direction, full material, flat anchor, extents, and indices. It checks corners, both outward triangles, the diagonal, exact index patterns, and coverage counts. Two halves of dense occupancy enumeration run independently. Full Atelier acceptance does not use this per-cell, per-face scan.

`tests/geometry_dump.bend` serializes each original Body before `Mesh.build`, then emits the returned Body and complete packed arrays through production imports. `tools/geometry_oracle.py` derives occupancy from the original alone and requires exact returned Body equality, including rejection cases. It checks every exterior unit face, material, multiplicity, internal-face absence, packed corner, metadata field, index, zero padding, capacity, bound, and logical size. Fixtures include touching materials, cavities, high material IDs, empty inputs, rejected overlaps, coordinate bounds, invalid dense shapes, and size overflow. `tools/geometry_clips.py` checks all 10,000 valid rectangle pairs over the 0 through 4 grid against independent set subtraction. `tools/check_geometry.py` also requires byte-identical native output with one and six CPU threads.

The pinned Atelier has 803,970 occupied cells, 423,136 exterior unit faces, and 10,304 quads. The actual 512-square viewport ray at 226,224 with `Camera.atelier()` removes 16 material-4 cells. The carved Body has 803,954 occupied cells, 423,162 faces, and 10,359 quads. Repeat changes zero cells. Reset restores the exact original Body and packed arrays.

`tests/geometry_device.bend` uploads the checked full-scene Mesh directly and compares actual Vulkan buffer readback with CPU arrays retained before upload. Intact vertex and index lengths are 1,648,640 and 247,296 bytes. Carved lengths are 1,657,440 and 248,616 bytes. Repeat and reset require exact readback equality. Camera-only frames preserve bytes and upload counts. Size rejection checks exercise both logical U64 lengths before resource changes. Empty geometry allocates no buffers. Replacements preserve row counts, and scope completion leaves zero rows.

A separate small cuboid fixture renders asymmetric rectangles through the basic diagnostic pipeline. Readback covers all six directions and the complete eight-material set. A camera inside the closed fixture requires clear pixels and depth, proving back-face culling. Literal GPU owning-cell identity at internal cell boundaries and rectangle outer edges remains deferred to the appearance shader unit. These rectangle checks make no passed cell-identity claim.

`fixtures.bend` separately checks the main intact and carved occupancy against an explicit cell-center distance formula. Repeated carving is idempotent. Reset restores the exact intact image. The run also checks an internal cavity, an empty body, and an adjacent eight-material strip.

`reference.bend` has an analytic ray/plane oracle independent of upstream hit selection. It also compares the selected material, direction, and normalized depth against upstream `Pixel.hit` on the same validated geometry and camera. The basic GPU frame is compared to the upstream basic palette, rather than the old renderer's lighting and ground.

The edge policy is fixed before comparison. Projected face and rectangle polygons are clipped at the near plane. Their boundary segments define an inclusive Euclidean one-pixel band around pixel centers. Internal triangle diagonals never define exclusions. The report prints the excluded pixel count for every frame. Outside the band, occupancy and diagnostic bytes must match exactly, basic RGB may differ by at most one byte, and normalized depth has absolute tolerance `2e-5`.

Band pixels still have to represent valid geometry. Covered GPU pixels must match a face intersection, material/direction or basic color, and depth, with a `1e-4` cell-coordinate allowance for raster edges. They may not be behind the nearest oracle surface by more than the depth tolerance. A clear pixel is accepted only where no face has a strict interior intersection after a `1e-4` cell inset. Thus the band does not excuse interior cracks or arbitrary colors.

Diagnostic renders cover all six directions and material IDs `1,2,3,4,5,0x80000000,0x89abcdef,0xffffffff`. Both material and direction passes compare actual GPU readback. Visibility masks require every material and direction to have been observed. Camera-only frames compare mesh bytes before and after, check the upload counter, and render a moved camera. Eight carve/reset replacement cycles check the live-resource count after each replacement. Empty geometry has four fewer live rows. Scope completion requires zero rows.

The normal Bend checker accepts the claims in `LAWS.bend` and `PROOF.bend` for pure material-word preservation, byte packing examples, direction codes, face counts, symbolic quad-index patterns, both outward triangle normals, and all quad-index bounds across the 3,072-face fixture limit. The checked count recurrence is universal over face, tail, and starting count, including its explicit limit failure branch. Additional laws preserve rectangle material and direction, clipped-list materials, asymmetric winding, checked size limits, and U64 byte limbs. General clipping coverage and disjointness are not universally proven. They use exhaustive small-grid subtraction and exact original-Body fixture checks.

`bend PROOF.bend` remains the required normal-checker gate. The independent kernel has not validated the combined proof file. The retained 3,072-quad index-bound law has a checker/kernel mismatch in the reviewed scratch artifact and its unchanged corresponding baseline. No assertion or fixture capacity is reduced to avoid it. These laws do not prove floating-point camera arithmetic, native code, or shaders. Those use executed geometry and GPU checks.

Run the complete gate with:

```sh
python3 tools/verify.py --sanitize
```

The verifier checks the dependency pin, shader and binding freshness, proofs, all previous consumers, the voxel native artifact, Khronos and synchronization validation when installed, and real voxel execution under ASan and UBSan. Logs and emitted C remain in `build/`. Driver-global leak detection is disabled, as in the existing suite. Explicit wrapper row checks cover cleanup. The offscreen checkpoint implements basic colors and exports. The [interactive consumer](presentation.md) adds native presentation and controls. Production appearance, GPU owning-cell edge diagnostics, and brush preview remain for the next milestone 6 unit. The native default remains the cube.
