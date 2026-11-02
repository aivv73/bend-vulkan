# Native Vulkan bindings for Bend: explicit GPU memory, command recording, synchronization, and indexed graphics on 64-bit Linux. Source: https://entire.com/et/bend-engine/bend-vulkan
# BendHub package entry: import Vulkan.bend for the public API.
# Native effects require Bend 2.0.39. Build examples with -o for native execution.
import ./Vulkan.bend as Vulkan
import ./src/core.bend as Core
import ./src/constants.bend as Constants
import ./src/upload.bend as Upload
import ./PROOF.bend as Proof
import ./examples/discover.bend as Discover
import ./examples/buffer_roundtrip.bend as BufferRoundtrip
import ./examples/offscreen_roundtrip.bend as OffscreenRoundtrip
import ./examples/indexed_offscreen.bend as IndexedOffscreen
import ./examples/indexed_window.bend as IndexedWindow
import ./examples/PROOF.bend as ExampleProof
