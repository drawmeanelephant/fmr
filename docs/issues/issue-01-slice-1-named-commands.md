# Slice 1: Named Commands (`fmr check` and `fmr run`)

**Slice**: 1 (Core Execution)  
**Parent Plan**: [`yard-plan.md`](../../yard-plan.md) (Sections 2.1, 4, 8, 9)  
**Depends On**: Slice 0 (Completed)

---

## 1. Goal & Context

Implement the named command execution layer in `fmr`:
1. `fmr check [repo...]` — Run check/test commands sequentially across all or named repositories.
2. `fmr run <repo> <command> [extra_args...]` — Execute repository-specific custom commands with proper environment variables, placeholder expansion, and working directory isolation.

This separates sync (fast-forward git state) from test/execution, honoring the principle that build and test suites should never parallel-stampede system resources (sequential execution policy).

---

## 2. CLI Signatures & Expected Behavior

### `fmr check [repo...]`
- If repos are specified (e.g. `fmr check boris oliver`), run checks for those repos only.
- If no repos specified (or `--all` / `-a`), run checks across all configured repos.
- **Resolution Order for check command**:
  1. `repos[i].check.argv` if defined.
  2. `defaults[kind].check.argv` if defined for repo's `kind` (e.g. `zig` -> `["zig", "build", "test"]`, `go` -> `["go", "test", "./..."]`, `node` -> `["npm", "test"]`).
  3. If neither is defined, print `[skip]` (info) and continue without failure.
- **Sequential Policy**: Checks must be run **serially** (`jobs: 1`), never concurrently.
- **Working Directory**: Must be the repo's primary checkout (`{repo}`).
- **Exit Code Contract**:
  - Exit `0`: All executed checks exited with 0.
  - Exit `2`: Unknown repo name provided.
  - Exit `4`: Subprocess exited with non-zero code. Print `[fail] <repo>: <command> exited with code <N>`.

### `fmr run <repo> <command> [extra_args...]`
- Executes a named command defined under `repos[i].commands[<command>]` or `defaults[kind].commands[<command>]`.
- **Working Directory**: Must be set to the repo's primary checkout.
- **Environment**: Set `FMR_REPO=<absolute_path_to_primary>` (and `YARD_REPO` for compatibility).
- **Placeholder Expansion**: Expand `{workspace}`, `{repo}`, `{name}`, `{branch}` in configured argv.
- **Extra Arguments**: Any trailing CLI arguments after `<command>` are forwarded directly to the spawned process.
- **Exit Code Contract**:
  - Exit `0`: Subprocess completed with exit code 0.
  - Exit `2`: Unknown repo name or command `<command>` not defined for that repo.
  - Exit `4`: Subprocess exited with non-zero code.

---

## 3. Files to Touch / Create

- [`src/main.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/main.zig): Wire `check` and `run` command dispatch.
- [`src/config.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/config.zig): Add support for repo-level and kind-level `check` and `commands` schema definitions.
- [`src/exec.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/exec.zig) *(new)*: Subprocess runner handling placeholder expansion, sequential execution, formatted output, and exit code aggregation.
- [`src/test_e2e.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/test_e2e.zig): Add E2E fixture test scenarios covering:
  - `fmr check` using repo kind default.
  - `fmr check` using repo-specific check argv.
  - `fmr check` on repo with no check defined (`[skip]`).
  - `fmr check` failing command returning exit 4.
  - `fmr run <repo> <command>` with argument forwarding and env validation.
  - `fmr run <repo> unknown_cmd` returning exit 2 listing available commands.

---

## 4. Acceptance Criteria

- [ ] `zig fmt --check src/*.zig build.zig` passes cleanly.
- [ ] `zig build test` passes all unit tests including new config and command parsing tests.
- [ ] `zig build test-e2e` passes with new E2E test assertions for `check` and `run`.
- [ ] Running `fmr check` without arguments runs all configured checks sequentially without stampeding CPU.
- [ ] Running `fmr run <repo> <cmd>` runs in the repo directory and passes extra arguments.
