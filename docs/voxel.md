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

`Mesh.build` returns the owned dense body and `Mesh`, containing the exposed-face list, face count, and vertex/index arrays. The consumer uses dense bodies only. Rectangular cuboid surfaces are rejected by the independent geometry check. The acceptance fixture is bounded to 8³ cells and at most 3,072 exposed faces.

`Renderer.replace_mesh` releases the previous geometry and uploads the exact logical lengths of both new arrays. An empty mesh owns no vertex or index buffers. Calls occur after the previous synchronous frame has observed its fence and reset its command buffer. `Renderer.frame` accepts a camera and diagnostic mode. It records, submits, waits, reads RGBA8 and D32 staging bytes, and resets the command and fence. It neither meshes nor uploads geometry.

Mesh buffers use host-visible memory. A HOST_WRITE to VERTEX_INPUT barrier publishes their vertex and index contents. Images use explicit color/depth attachment and transfer-source transitions. The staging transfer is made visible to the host after fence completion. Scope cleanup uses the existing Vulkan resource graph. Replacements explicitly destroy buffers before freeing their allocations.

## Packed data

Every exposed unit face has four vertices and six U32 indices. The triangle pattern is `0,1,2,2,3,0`, relative to the face's first vertex. Vertex stride is 20 bytes:

| Byte offset | Contents | Vulkan format |
| --- | --- | --- |
| 0 | XYZ, three F32 words in voxel units | R32G32B32_SFLOAT |
| 12 | R, G, B, direction, one byte each | R8G8B8A8_UNORM |
| 16 | Complete material U32, little endian | R8G8B8A8_UNORM |

Direction codes are `-X,+X,-Y,+Y,-Z,+Z` as `0,1,2,3,4,5`. The vertex shader recovers bytes with `round(attribute * 255)` and sends flat metadata to the fragment shader. The basic fragment shader outputs alpha one. The material diagnostic writes all four material bytes, including alpha. The direction diagnostic writes the direction byte to red and alpha one.

Basic colors come from upstream `material.Palette.surface` and `render.Face.light`, including the magenta fallback for unknown positive IDs. This byte encoding is display RGB in an RGBA8 UNORM target. No second sRGB conversion occurs. Mesh extraction and shader interpretation remain consumer responsibilities.

Binding offsets and base vertex are zero. Quads have outward winding. The camera uses the upstream basis and pixel-center rays at 512 by 512. Camera-local XYZ maps to clip `(420/256*X, -420/256*Y, Z-near, Z)`. The positive-height viewport uses counterclockwise front faces and back-face culling. D32 depth is `1-near/Z`, with near 0.1 and an infinite far plane. Push constants are a 64-byte column-major matrix.

## Verification policy

`geometry.bend` independently enumerates every dense cell and all six signed neighbors. It compares the complete exposed-face multiset, including material and multiplicity, against upstream extraction. It decodes every packed position, color/direction word, material word, and index. It checks unit corners, both outward triangles, the quad diagonal, exact index patterns, and coverage counts. This detects missing, duplicate, interior, and material-altered faces. Two equally sized halves of the occupancy enumeration run as independent pure CPU branches. Each half walks its work sequentially. This decomposition makes no throughput claim.

`fixtures.bend` separately checks the main intact and carved occupancy against an explicit cell-center distance formula. Repeated carving is idempotent. Reset restores the exact intact image. The run also checks an internal cavity, an empty body, and an adjacent eight-material strip.

`reference.bend` has an analytic ray/plane oracle independent of upstream hit selection. It also compares the selected material, direction, and normalized depth against upstream `Pixel.hit` on the same validated geometry and camera. The basic GPU frame is compared to the upstream basic palette, rather than the old renderer's lighting and ground.

The edge policy is fixed before comparison. Projected unit-face polygons are clipped at the near plane. Their boundary segments define an inclusive Euclidean one-pixel band around pixel centers. Internal triangle diagonals never define exclusions. The report prints the excluded pixel count for every frame. Outside the band, occupancy and diagnostic bytes must match exactly, basic RGB may differ by at most one byte, and normalized depth has absolute tolerance `2e-5`.

Band pixels still have to represent valid geometry. Covered GPU pixels must match a face intersection, material/direction or basic color, and depth, with a `1e-4` cell-coordinate allowance for raster edges. They may not be behind the nearest oracle surface by more than the depth tolerance. A clear pixel is accepted only where no face has a strict interior intersection after a `1e-4` cell inset. Thus the band does not excuse interior cracks or arbitrary colors.

Diagnostic renders cover all six directions and material IDs `1,2,3,4,5,0x80000000,0x89abcdef,0xffffffff`. Both material and direction passes compare actual GPU readback. Visibility masks require every material and direction to have been observed. Camera-only frames compare mesh bytes before and after, check the upload counter, and render a moved camera. Eight carve/reset replacement cycles check the live-resource count after each replacement. Empty geometry has four fewer live rows. Scope completion requires zero rows.

`LAWS.bend` and `PROOF.bend` state and prove pure material-word preservation, byte packing examples, direction codes, face counts, symbolic quad-index patterns, both outward triangle normals, and all quad-index bounds across the 3,072-face fixture limit. Arithmetic counts use U32 semantics; the bounded fixture laws do not claim arbitrary-size meshes cannot overflow. These laws do not prove upstream extraction, floating-point camera arithmetic, native code, or shaders. Those use executed geometry and GPU checks.

Run the complete gate with:

```sh
python3 tools/verify.py --sanitize
```

The verifier checks the dependency pin, shader and binding freshness, proofs, all previous consumers, the voxel native artifact, Khronos and synchronization validation when installed, and real voxel execution under ASan and UBSan. Logs and emitted C remain in `build/`. Driver-global leak detection is disabled, as in the existing suite. Explicit wrapper row checks cover cleanup. This checkpoint implements basic colors and offscreen exports. Interactive presentation and production appearance remain later milestones.
