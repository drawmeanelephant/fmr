# Slice 2: Immutable RAG Snapshots (`fmr rag`)

**Slice**: 2 (RAG Snapshot Pipeline)  
**Parent Plan**: [`yard-plan.md`](../../yard-plan.md) (Sections 2.1, 4, 8, 9)  
**Depends On**: Slice 0, Slice 1

---

## 1. Goal & Context

Implement the RAG export pipeline (`fmr rag [repo...] [--force]`):
1. Create content-addressed, immutable snapshot directories at `paths.sourceRag/<name>/<sha40>/`.
2. Atomically manage the `paths.sourceRag/<name>/current` symlink to point to the latest commit snapshot.
3. Support two export modes:
   - **`files` mode**: Fast, zero-subprocess file copying using glob filters (`globs: ["*.md", "*.toml"]`) and depth limits (`max_depth`).
   - **`command` mode**: Invokes custom exporter script/binary with `{rag_out}` pointing to a temporary staging folder (`<sha>.staging`), safely promoted on success.
4. Provide idempotency: if `<sha40>` already exists and is complete, skip without re-exporting unless `--force` is specified.

---

## 2. Architecture & Safety Rules

```
~/Code/source-rag/
├── boris/
│   ├── a1b2c3d4...40sha/           # Snapshot directory for specific commit SHA
│   │   ├── manifest.json            # Snapshot metadata (commit, branch, timestamp, mode, files)
│   │   └── ...                      # Exported markdown, docs, or indexed files
│   └── current -> a1b2c3d4...40sha  # Atomic symlink pointing to latest valid snapshot
```

### Safety & Invariants
- **Staging Directory Isolation**: Exporters run against a staging folder `paths.sourceRag/<name>/<sha>.staging`. If the exporter fails (non-zero exit code):
  - Staging directory is cleanly cleaned up.
  - The existing `current` symlink is left completely untouched.
  - Returns exit code `4`.
- **Atomic Symlink Update**: On successful export (or staging directory completion), a relative or absolute symlink `current` is atomically created/replaced using `symlink` / `rename`.
- **Idempotency**: Running `fmr rag` twice on an unchanged HEAD commit is a fast no-op returning `[snap ok] (up to date)`. `--force` re-runs the export and replaces the snapshot directory.
- **Sequential Policy**: Snapshots are processed sequentially (`jobs: 1`) to prevent I/O disk saturation.

---

## 3. Configuration Schema Additions

```json
{
  "repos": [
    {
      "name": "boris",
      "rag": {
        "command": {
          "argv": ["python3", "{workspace}/scripts/export_boris_rag.py", "{rag_out}"],
          "output": "{rag_out}"
        }
      }
    },
    {
      "name": "oliver",
      "rag": {
        "files": {
          "globs": ["*.md", "*.toml", "*.json"],
          "max_depth": 2
        }
      }
    }
  ]
}
```

### `manifest.json` Format
Every generated snapshot directory contains `manifest.json`:
```json
{
  "repo": "boris",
  "commit": "35896fc7c4270b2f5cbb66df5f80b2a758798bf1",
  "branch": "main",
  "timestamp": "2026-08-16T17:00:00Z",
  "mode": "command",
  "command": ["python3", "/path/to/script.py", "/path/to/staging"],
  "untracked_files_count": 0,
  "files_exported": 14
}
```

---

## 4. Files to Touch / Create

- [`src/rag.zig`](../../src/rag.zig) *(new)*: RAG snapshot coordinator, staging manager, file glob copier, atomic symlinker, and manifest writer.
- [`src/config.zig`](../../src/config.zig): Parse `rag.command` and `rag.files` structures.
- [`src/main.zig`](../../src/main.zig): Wire `rag` command dispatch and `--force` flag.
- [`src/test_e2e.zig`](../../src/test_e2e.zig): Add E2E fixture test scenarios covering:
  - `rag` with `command` mode: validates staging, manifest, and `current` symlink.
  - `rag` idempotency on second run without changes.
  - `rag --force` re-executing export.
  - `rag` failure leaving `current` symlink and previous snapshots untouched.
  - `rag` with `files` mode using globs and directory depth.

---

## 5. Acceptance Criteria

- [ ] `zig fmt --check src/*.zig build.zig` passes cleanly.
- [ ] `zig build test` passes all unit tests.
- [ ] `zig build test-e2e` passes with full RAG snapshot assertions.
- [ ] Snapshot directory contains valid `manifest.json` and exported artifacts.
- [ ] `current` symlink points reliably to `<sha40>`.
