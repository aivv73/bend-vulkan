# Upload foundation review

Scope was committed `4657f75` against `928bee9`. Root and one independent `gpt-6.1-sol` reviewer inspected the source. The reviewer also checked the supplied execution logs and generated bindings. This review did not run a new device reproducer.

One actionable finding required correction. `Upload.reserved` switched to the candidate staging allocation even if retirement of the original allocation failed. An active recording could cause that rejection. The original buffer and memory remained live and unretired, so later collection could not reclaim them.

Retirement and collection need separate outcomes. Rejected retirement must dispose of the candidate and return the original owner. Successful retirement can switch owners before collection. Verification must exercise rejected growth, the original handle and bytes, stable rows, and a later successful growth.

The independent review reported no additional actionable issues in subrange arithmetic, returned arrays, sealing, collection iteration, failed reset retention, or renderer replacement rollback.

The task result is recorded by T3 as `m7-upload-correctness-review-r1`. The root forwarded the same finding to the active implementation owner before this result arrived.

Commit `c3f612d` resolves the rejected-growth path. Root inspected its diff and the execution logs. The new real-device check asserts the original handle and capacity, unchanged live rows, and the subsequent literal GPU readback. Native controlled probes and `bend PROOF.bend` passed again in `build/m7-native-grow.log` and `build/m7-proof-grow.log`.

The correction destroys the unused candidate directly when retirement rejects the old storage. Successful retirement switches owners before collection and reports collection failure as committed growth. Native collection only fails for an invalid owner or device loss. No recursive cleanup states or retry loop were retained.
