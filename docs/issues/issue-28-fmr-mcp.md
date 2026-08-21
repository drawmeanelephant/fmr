# Issue 28: `fmr mcp` — MCP Server for Claude/Cursor (M2 — Personal)

**Milestone**: M2 v0.3 Personal (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig) + Docs  
**Size**: M (2–3h)  
**Depends On**: #26 (`context` shape)

---

## 1. Goal & Context

Right now agents (Claude Code, Cursor) call `git` directly and can violate the safety invariants (`reset --hard`, cloning into primaries, forgetting the Conductor worktree contract). T3 bakes fleet management into the agent — fmr should bake *safety* into the agent by being the only tool the agent is allowed to use for workspace git.

Model Context Protocol (MCP) over stdio is the standard. One binary, no daemon:

```
fmr mcp  # speaks MCP JSON-RPC on stdin/stdout
```

Cursor/Claude config then points at `fmr mcp` and the agent gets `status`, `sync`, `doctor`, `context`, `grep`, `run` as typed tools instead of shelling `git`.

## 2. Specification

### Transport

- Stdio JSON-RPC 2.0 per MCP spec (`initialize`, `tools/list`, `tools/call`, `notifications/*`). No HTTP/SSE in v1.
- `fmr mcp --config <path>` respects config override. Logs to stderr, never stdout (stdout is JSON-RPC).

### Tools exposed (v1)

| Tool | Maps to | Args |
|---|---|---|
| `fmr_status` | `status --json` | `repos?: string[]` |
| `fmr_sync` | `sync --json` | `repos?: string[], jobs?: number, fixOrigin?: boolean` |
| `fmr_doctor` | `doctor --json` | `fix?: boolean` |
| `fmr_context` | `context --json` | `repos?: string[], commits?: number` |
| `fmr_grep` | `grep --json` | `pattern: string, repos?: string[], kind?: string` |
| `fmr_run` | `run --json` | `repo: string, command: string, args?: string[]` |
| `fmr_config` | `config` | _(none)_ |

Each `tools/call` reuses the existing `src/*.zig` run paths internally (no subprocess spawn of `fmr` itself) — factor a `lib.zig` entry point or call the same functions `sync.run` etc with a captured buffer. For v1 it’s acceptable to spawn `fmr` subprocesses per call (simpler, isolates), but document the tradeoff.

### Files to touch

- `src/mcp.zig` *(new, ~350 lines)* — JSON-RPC loop: read lines from stdin, parse `json.Value`, dispatch, write responses. Uses `std.json` and `std.Io`. No external deps. Hand-codes MCP handshake; keep it minimal (no SDK).
- `src/main.zig` — dispatch `mcp`, never returns (loop until EOF).
- `docs/MCP.md` *(new)* — client config snippets for Claude Code (`claude mcp add fmr -- fmr mcp --config ...`) and Cursor (`~/.cursor/mcp.json`).
- `src/test_e2e.zig` — drive `fmr mcp` with a synthetic `initialize` + `tools/call` sequence, assert JSON-RPC responses.

### Security

- Never expose `delete-files` or hard resets. Tool list is allowlisted; `fmr remove --delete-files` is not exposed via MCP.
- All mutations (`sync`, `run`) still go through safety checks (`state.zig`).

## 3. Acceptance Criteria

- [ ] `echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | fmr mcp` returns `{"result":{"protocolVersion":"...","tools":[...]}}`.
- [ ] `tools/call` for `fmr_status` with `{"repos":["boris"]}` returns same JSON as `fmr status boris --json` inside the RPC envelope.
- [ ] Claude Code can register `fmr mcp` and call `fmr_context` without shelling `git`.
- [ ] `zig build test && zig build test-e2e` green (MCP handshake + 2 tool calls).
