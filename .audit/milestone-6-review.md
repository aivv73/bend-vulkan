# Milestone 6 verification record

The completion contract is [milestone-6-contract.md](milestone-6-contract.md). The selected design is [milestone-6-design.md](milestone-6-design.md). The append-only [decision trail](milestone-6.tsv) records failed approaches and their corrections.

## Verified units

The complete baseline passed before implementation. Descriptor commit `19b53ef` passed the complete gate and is [PR #4](https://github.com/aivv73/bend-vulkan/pull/4). Exterior commit `247e4da` passed the complete gate and is [PR #5](https://github.com/aivv73/bend-vulkan/pull/5).

The complete command is:

```bash
env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display
```

Baseline, descriptor and exterior logs are `build/milestone-6-baseline.log`, `build/milestone-6-descriptor-verification.log` and `build/milestone-6-geometry-verification.log`. The final complete appearance run passed in `build/milestone-6-appearance-verification.log`, including sanitizers, validation, acquisition consistency, both native queue configurations and the quiet product check.

## Independent acceptance

The original-Body geometry oracle checks exact exterior coverage, material and multiplicity. It checks 10,000 clipping pairs and byte-identical output with one and six CPU threads. Intact Atelier contains 803,970 occupied cells, 423,136 exterior unit faces and 10,304 quads. The tested cut removes 16 cells. Repeated cutting changes zero cells and reset restores the original state.

Actual production readbacks pass in normal execution, validation and ASan/UBSan runs. The final sanitized oracle checks 1,360,105 exact identity pixels and 18,905 lighting samples. It checks raw versus shaded coverage, once-only display conversion, tint and rings. Four literal raster-fringe cases preserve the front material and owning cell. Independent negative controls reject wrong tangential cells, missing visible rings and linear eye-depth interpolation.

The original reference uses an effective 512-square shadow map for Atelier. Its base setting of 128 is overridden for this scene. Cached reference visibility, original direct visibility and actual GPU depth remain separate comparisons.

The shadow gate checks every direct and cache-leaf tap of the sunny original receiver fixtures, plus production-coordinate taps at those receivers. It checks 1,746 intact and 1,747 carved tap coordinates. It finds zero unexplained selected depths. Each accepted depth has an original-caster witness under explicit floating-point and device subpixel bounds. Mandatory closer faces and complete box silhouettes constrain deeper alternatives. The two caster substitutions also require discrete grid coverage evidence.

Five corruption controls must fail. They replace the map with clear depth, replace it with zero, shift it one texel, add a stable depth spike, or invent a depth at the disputed edge tap. Actual-data CLI status is zero. Each corruption CLI status is one. Parent replay and the independent correctness reviewer reproduced those outcomes.

The shadow model covers the named selected taps. It does not certify every shadow texel or replay the exact GPU instruction sequence. Its precision evidence comes from the actual NVIDIA GeForce GTX 1660 with driver 615.71.09 and eight subpixel bits.

## Source provenance

The shadow oracle was integrated while the original production runner was already loaded. Its added pure checks execute separately through `python3 tools/check_production.py --shadow-only`. That command uses coherent snapshots and does not render again.

The parent regenerated production C from the current Bend and shader inputs. It is byte-identical to the input of the completed sanitizer compile. Its SHA256 is `31148bdbc6dd23fe4c936c172a5e651d3e94e43b67c3ad545136c2f2f2516461`. Evidence is `build/milestone-6-parent-production-source-freeze.log`. All nine legacy SPIR-V exports remain word-identical to the verified exterior commit. Evidence is `build/milestone-6-parent-legacy-shader-freeze.log`.

The parent also regenerated the native probe C through the checked-in instrumentation helper. It is byte-identical to the actual sanitizer compiler input. Its SHA256 is `f69c20db2e4f009b520f9875961e552160b558e0e8b9f30b54b29048d16c193b`. Evidence is `build/milestone-6-parent-native-source-freeze.log`. Only emission was repeated. Clang and GPU execution were not repeated for this comparison.

## Proof limits

Normal `bend PROOF.bend` passes. The optional independent kernel has a mismatch on the retained 3,072-quad bound fixture and its corresponding unchanged baseline. No assertion or fixture capacity was reduced. General clipping coverage and disjointness use exhaustive small-grid checks and exact original-Body fixtures rather than a universal proof. Native code and shaders require runtime evidence.

## Review choices

| Principle | Concrete choice |
|---|---|
| Foundational Thinking | Choose resource ownership and frame data before implementing appearance. |
| Model the Domain | Keep CPU world state in `World` and one GPU group in `Session`. |
| Exhaust the Design Space | Compare three architecture candidates and use an independent judge. |
| Separate Before Serializing Shared State | Give one worker the checkout and put independent artifacts in separate scratch directories. |
| Sequence Work into Verifiable Units | Verify descriptors, exterior geometry and appearance in dependency order. |
| Build the Lever | Commit rerunnable geometry, shader, lighting, shadow and native acceptance tools. |
| Boundary Discipline | Reject unsupported native schemas, coordinate ranges and overlapping cuboids at their input boundaries. |
| Type System Discipline | Use typed descriptor slots and explicit frame phases. |
| Migrate Callers Then Delete Legacy APIs | Migrate all pipeline-layout constructors and mesh stride readers together. |
| Redesign from First Principles | Separate CPU state from GPU ownership and prepare each acquired frame from the latest revision. |
| Laziness Protocol | Reuse the ownership graph, shader builder and recorder instead of adding a render graph or frame system. |
| Guard the Context Window | Keep bulk artifacts in worker directories and review their exact outputs. |
| Test Behavior, Not Implementation | Check real readbacks and prove deliberate corruptions fail. |
| Fix Root Causes | Reject the diagnostic-discard workaround and retain covered front fragments. |
| Encode Lessons in Structure | Add literal boundary regressions, full coverage equality and negative controls for the observed acceptance holes. |
| Prove It Works | Require real Vulkan and X11 evidence, source correspondence and explicit execution outcomes. |

## Review status

The fresh production correctness review found no remaining confirmed renderer defect or false-acceptance case. The final full execution gate passed. The implementation owner returned and froze source after the final pure shadow gate passed. Parent proof, generation freshness, whitespace and native capture checks pass. The final source commit is `981ff80`. The staged check removed only two trailing blank lines in new test files after the freeze. The parent reran normal proof before this commit.

The fresh final trail reviewer, `gpt-5.6-sol`, returned no flags. The reviewer checked the actual logs, causal results, six command statuses and source hashes. The review closed the earlier final-snapshot concern through split verification. It did not claim a second full GPU run. The identity-fix closure row also resolved the earlier trail gap.

Comment reviews accepted 24 deletions in the main appearance unit and one class-docstring deletion in the ported shadow module. The optional scratch supervisor was not ported. No comment was restored. One fresh reassessment withdrew four unsupported reshape flags. There are no open comment constraints or encoding offers. Earlier descriptor and geometry units removed four and one comments respectively.

The first trail review used `gpt-5.6-sol`. Its missing identity-fix closure row is now appended. Its final-snapshot concern is addressed through exact emitted-C correspondence, the separate canonical pure gate and the completed full run. The sanitized production oracle inside that run also executes the integrated causal shadow check. The fresh final review accepted this evidence.

## Delivery

The dependency order is [PR #4](https://github.com/aivv73/bend-vulkan/pull/4), [PR #5](https://github.com/aivv73/bend-vulkan/pull/5), then [PR #6](https://github.com/aivv73/bend-vulkan/pull/6). The source commits are `19b53ef`, `247e4da` and `981ff80`. The final PR targets `t3code/m6-exterior`. GitHub reports it open and ready, and T3 registration succeeded immediately after creation. This audit record follows the source in a separate documentation commit. No merge or deployment is part of this delivery.
