# Principles that changed milestone 7 decisions

| Principle | Concrete choice | Evidence |
| --- | --- | --- |
| Model the Domain | Represent frame slots as Free, Acquiring, Submitted, Presenting and Discarding. Keep submission order separate from body revision. | `examples/voxel/flight.bend`, ordered acquisition fixture |
| Foundational Thinking | Freeze device references and frame-local data at acquisition. Retain a small submitted receipt instead of duplicate CPU meshes and uniforms. | Frame architecture and `tests/appearance_acquisition.bend` |
| Type System Discipline | Distinguish shared Target from SlotTarget. Each type has one destruction contract. | `examples/voxel/presentation.bend` |
| Separate Before Serializing Shared State | Give each slot its own mutable resources. Keep one source writer and serialize device measurements. | Workflow, per-slot assets and decision trail |
| Exhaust the Design Space | Compare three initial architectures and three retirement designs, then have fresh judges select and graft them. | Design and retirement notes |
| Attack the Premise | After staging and publication failures shared the retirement premise, inspect command usability before changing its policy. Retain the Recording guard and make whole-set retirement atomic. Reject the later malformed-array counterexample after the actual native constructor fails before serialization. | Partial-publication reproduction and retirement design |
| Redesign from First Principles | Publish a complete geometry generation at one atomic native boundary. Make obsolete knowledge visible before later presentation dispatch. | Retirement design and recovery investigation |
| Boundary Discipline | Validate every external allocation pair before sealing any of them. Internal generation code supplies the complete obsolete set. | Native retirement implementation |
| Migrate Callers Then Delete Legacy APIs | Replace scalar retirement with the batch API and migrate generated declarations, registration and callers together. | Bindings schema and generated files |
| Laziness Protocol | Keep the installer API. Remove unused packet data and duplicate target attachments. Skip generation preparation and commit on unchanged revisions. | Retirement judge and full review |
| Subtract Before You Add | Remove root depth/framebuffers before allocating attachments solely through slot ownership. | Typed target correction |
| Build the Lever | Keep exact chunk, ownership, input and measurement checks as rerunnable repository tools. | `tools/check_chunks.py`, `tools/check_acquisition.py`, `tools/check_measurement.py` |
| Encode Lessons in Structure | Encode completion tags, timing numeric decoding and wrong-output rejection in the portable measurement gate. | 25 pure measurement cases |
| Test Behavior, Not Implementation | Assert literal GPU bytes, all 2,336 uniform bytes, exact geometry identity, image causality and observed resource counts. | Device fixtures and appearance gates |
| Fix Root Causes | Reproduce partial publication with an index-only Recording command. Preserve the exact resize trace before changing recovery. Trace the legacy row-count failure to its missing collection after caller ownership selection. | Publication reproduction and hashed recovery traces |
| Sequence Work into Verifiable Units | Verify upload ownership, pure chunks and device generations before frame integration. Publish only coherent PR endpoints after corrections. | Decision trail and checkpoint commits |
| Prove It Works | Require actual release and sanitizer device execution. Keep failed and stopped builds distinct from passes. | Saved logs and review dispositions |
| Explain the Number | Count rendering plus presentation-resource handoff, retain image eligibility gates, and tune CPU workers and frame slots separately. Physical display completion remains unavailable. | Measurement review and workflow |
| Guard the Context Window | Delegate source exploration and reviews. Keep fixed source captures and summarized dispositions in the root thread. | Review captures and audit notes |
| Never Block on the Human | Continue reversible implementation and verification under the original request. Resolve observable design forks through probes. | Autonomous workflow |
