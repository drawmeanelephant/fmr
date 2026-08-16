# Slice 4: Script Retirement, Retention GC (`--gc`), & JSON Output (`--json`)

**Slice**: 4 (Retirement, Housekeeping & Tooling)  
**Parent Plan**: [`yard-plan.md`](../../yard-plan.md) (Sections 4, 8, 9, 10)  
**Depends On**: Slice 0, Slice 1, Slice 2, Slice 3

---

## 1. Goal & Context

Finalize `fmr` as the sole workspace management authority:
1. **Snapshot Retention GC (`fmr rag --gc <n>`)**: Clean up old snapshot directories, retaining only the `<n>` most recent snapshots per repository (while safeguarding the target pointed to by `current`).
2. **`fmr doctor --fix`**: Automated remediation tool to prune stale lock files (`~/.fmr/locks/`) from dead processes and optionally clean legacy unmanaged snapshot directories.
3. **Structured `--json` output**: Machine-readable JSON output for agentic tooling and scripts across `status`, `sync`, `doctor`, `check`, and `rag`.
4. **Retirement**: Decommission and remove legacy bash scripts (`proud-brahmagupta.sh`) after verifying zero-divergence parity.

---

## 2. Features Specification

### Snapshot GC (`fmr rag --gc <n>`)
- For each repository in `paths.sourceRag/<name>/`:
  - List all `<sha40>` subdirectories.
  - Sort snapshots by creation / manifest timestamp.
  - Delete older snapshot directories exceeding `<n>`, **strictly preserving**:
    - The snapshot directory currently linked by `current`.
    - Any snapshot directory created within the last 1 hour.
  - Print count and freed disk space (or structured summary).

### `fmr doctor --fix`
- Scans `~/.fmr/locks/` for locks held by PIDs that are no longer running (stale locks) and removes them.
- Prompts or verifies before removing orphaned directories.

### `--json` Flag
All commands accept `--json` to output pure, parseable JSON on stdout:
```json
{
  "command": "status",
  "repos": [
    {
      "name": "boris",
      "path": "/Users/user/dev/drawmeanelephant/boris",
      "status": "clean",
      "branch": "afterparty",
      "sha": "35896fc7c4270b2f5cbb66df5f80b2a758798bf1",
      "rag_current_sha": "35896fc7c4270b2f5cbb66df5f80b2a758798bf1"
    }
  ]
}
```

---

## 3. Files to Touch / Create

- [`src/rag.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/rag.zig): Add GC retention pruning logic.
- [`src/doctor.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/doctor.zig): Add `--fix` handler.
- [`src/main.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/main.zig): Add `--json` flag handling and output routing.
- [`src/status.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/status.zig), [`src/sync.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/sync.zig): Add JSON serialization builders.
- [`src/test_e2e.zig`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/src/test_e2e.zig): Add E2E tests for `--gc`, `--fix`, and `jq`-parseable `--json` output.

---

## 4. Acceptance Criteria

- [ ] `fmr rag --gc 2` retains only the 2 latest snapshots + `current` target.
- [ ] `fmr doctor --fix` safely clears stale locks with non-existent PIDs.
- [ ] `fmr status --json | jq .` parses valid JSON without ANSI escape sequences.
- [ ] Legacy bash scripts safely retired and documented.
