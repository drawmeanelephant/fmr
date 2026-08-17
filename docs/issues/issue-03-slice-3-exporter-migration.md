# Slice 3: Catalog Completion & Exporter Migration

**Slice**: 3 (Production Catalog & Compatibility)  
**Parent Plan**: [`yard-plan.md`](../../yard-plan.md) (Sections 4, 8, 9, 10)  
**Depends On**: Slice 0, Slice 1, Slice 2

---

## 1. Goal & Context

Migrate all 13 production workspace repositories into the `fmr` catalog (`workspace.json`), ensuring existing exporter scripts and project check definitions match reality:
1. Complete the catalog definition with all repositories:
   - Zig: `boris` (`default_branch: "afterparty"`), `oliver`, `DipshitOS`
   - Go: `know`, `codex-limits`
   - TypeScript / Node / Sites: `apex`, `filed.fyi`, `la-famille`, site repos, `minutes`, `rotkeeper`
   - Deliberately omitted: `rustodian` (removed from workspace catalog per design plan).
2. Ensure self-writing exporters (Python/Bash) are adapted to accept `{rag_out}` as an output argument while maintaining backward-compatible default fallback paths.
3. Validate running `fmr sync` and `fmr rag` end-to-end across the full production catalog alongside legacy tools during transition.

---

## 2. Catalog Specification Details

### Repositories Matrix
- **`boris`**: URL `git@github.com:drawmeanelephant/boris.git`, `kind: "zig"`, `default_branch: "afterparty"`, `worktree_safe: true`. Exporter: `export_boris_rag.py`.
- **`oliver`**: URL `git@github.com:drawmeanelephant/oliver.git`, `kind: "zig"`, `worktree_safe: false`. Mode: `files` mode (`globs: ["*.md", "*.toml", "*.json"]`).
- **`DipshitOS`**: `kind: "zig"`, `check: ["zig", "build", "test"]`.
- **`know`** / **`codex-limits`**: `kind: "go"`, `check: ["go", "test", "./..."]`.
- **`la-famille`**, **`filed.fyi`**, **`apex`**: Exporters updated with `{rag_out}` parameter.
- **`rotkeeper`**, **`minutes`**: Commands registered under `commands` object (e.g. `fmr run rotkeeper <cmd>`).

---

## 3. Files to Touch / Create

- Default config template at [`config/workspace.example.json`](../../config/workspace.example.json) or user config at `~/config/fmr/workspace.json`.
- Exporter wrapper scripts / python scripts in workspace repos to support `argv[1]` as target directory if provided, falling back to legacy flat `source-rag` directory if omitted.
- [`src/doctor.zig`](../../src/doctor.zig): Verify doctor handles all 13 repo configurations and accurately reports on root paths, branch statuses, and lock contention.

---

## 4. Acceptance Criteria

- [ ] Complete `workspace.json` passes `fmr doctor` with exit code 0.
- [ ] `fmr status` cleanly displays rows for all 13 configured repositories.
- [ ] `fmr sync --all` safely updates all 13 repositories without errors.
- [ ] `fmr check --all` executes checks on all repos with check definitions.
- [ ] `fmr rag --all` generates snapshots for all configured repos.
