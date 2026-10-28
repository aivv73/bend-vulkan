# Published revision verification, 2026-10-28

The library verifier and the new indexed-window example both passed from a fresh
clone of published `main`, revision `101e87ca0690070633fcf4777d68e27b0978ee31`.
The remote advertised this revision before verification.

Only `deps/bend-collections` was initialized, at its pinned revision
`bc78c4f4cabb536a2a1dd6e308b6a8f0afafda7c`. No recursive submodule initialization
was used. The clone had no `build/` directory before execution. Both the repository
and the dependency had empty `git status --porcelain=v1 --untracked-files=all`
output before and after the runs. Generated outputs are Git-ignored.

The checkout was `/tmp/bend-vulkan-published-rs0j6a1k/checkout`. Its creation and
dependency initialization are recorded in [checkout.log](checkout.log).
[result.json](result.json) records the environment, exact commands, timestamps,
exit codes, and Git status checks.

The host ran Linux x86-64 with glibc 2.44, Bend 2.0.39, Python 3.14.8,
Clang 23.1.4, glslc 2026.4, and SPIRV-Tools 2026.4. Vulkan discovery reported an
NVIDIA GeForce GTX 1660. Khronos validation was installed.

`python3 tools/verify.py` exited **0** at 17:41:23 UTC. `DISPLAY` and
`WAYLAND_DISPLAY` were unset for this run. Generation and shader freshness checks,
import boundaries, root and example proofs, headless examples, native ABI checks,
GPU integration, and controlled failure probes passed. Both proof entry points
reported `ALL PROOFS CHECK`. GPU checks also passed with Khronos and synchronization
validation enabled. This run did not use `--sanitize`.

The [library log](library.log) ends with:

```text
Controlled native probes and real GPU integration passed
Generation, proofs, and native Vulkan integration passed.
```

The validation result is retained in [validation.txt](validation.txt).

`python3 examples/verify_window.py` exited **0** at 17:41:35 UTC with `DISPLAY=:1`.
It compiled and executed `examples/indexed_window.bend` twice. Rendered colors,
camera movement and reset, repeated landscape and portrait resizing, unmap and
restore, Escape, and close while suspended passed with validation enabled.
Both executions reported `Indexed window closed; live Vulkan objects: 0`, with
no validation error, synchronization hazard, or VUID diagnostics.

The [window verifier log](window.log) ends with:

```text
Indexed window camera, repeated resize, unmap/restore, Escape and suspended close passed; zero live objects.
```

The individual process outputs are retained in
[indexed-window-escape.log](indexed-window-escape.log) and
[indexed-window-close.log](indexed-window-close.log).
Captures and all per-test logs remain in the original workspace's
`build/published-verification/` directory and the clean clone's `build/` directory.

The equivalent reproduction commands, with the README prerequisites installed,
are:

```sh
git clone --no-recurse-submodules --single-branch --branch main \
	entire://aws-eu-central-1.entire.io/et/bend-engine/bend-vulkan bend-vulkan-verify
cd bend-vulkan-verify
git checkout --detach 101e87ca0690070633fcf4777d68e27b0978ee31
git submodule update --init -- deps/bend-collections
git status --porcelain=v1 --untracked-files=all
env -u DISPLAY -u WAYLAND_DISPLAY python3 tools/verify.py
python3 examples/verify_window.py
git status --porcelain=v1 --untracked-files=all
git -C deps/bend-collections status --porcelain=v1 --untracked-files=all
```
