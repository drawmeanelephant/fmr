# Issue 16: Core — `fmr run --json` Structured Completion

**Area**: Core CLI (Zig)  \
**Parent Plan**: [`docs/gui/json-contract.md`](../gui/json-contract.md)  \
**Depends On**: None (all other commands already emit `--json`)

---

## 1. Goal & Context

Every `fmr` command emits a uniform `--json` envelope (`version` / `command` /
`exit` / `repos`) **except `fmr run`**, which streams subprocess output directly
and has no JSON mode. GUI clients currently consume `fmr run` via raw streaming
+ process exit code (works, but gives no typed result). This issue adds a
`--json` mode to `fmr run` so every command speaks the same contract.

**Design note**: `fmr run` has two consumers — the live console (wants streaming)
and the completion log (wants a typed result). `--json` is the typed path;
streaming stays the default and the GUI keeps using it for the live console.

## 2. Technical Specification

### CLI signature

```
fmr run <repo> <command> [args...] [--json]
```

When `--json` is given:

1. Run the subprocess exactly as today (cwd = primary, env injection,
   `FMR_REPO`/`YARD_REPO`, extra args forwarded verbatim).
2. **Capture** stdout/stderr (do not forward to the terminal).
3. On completion emit the standard envelope to stdout:

```json
{
  "version": 1,
  "command": "run",
  "exit": 0,
  "repos": [
    { "name": "boris", "result": "ok",     "exit": 0, "message": "command 'serve' exited 0" },
    { "name": "rotkeeper", "result": "failed", "exit": 4, "message": "command 'init' exited 2" }
  ]
}
```

- `result`: `ok | failed`.
- `exit`: the subprocess exit code (0 for ok; the actual code, mapped through the
  fmr contract — non-zero subprocess → `4` per the existing run contract, keep
  the subprocess code in `message`).
- Captured subprocess output goes to **stderr** of the fmr process (so stdout
  stays clean JSON), or is included in `message` when short.

### Files to touch

- `src/exec.zig`: `runCmd` gains a `json_out: bool` param; capture instead of
  forward when set; emit envelope.
- `src/main.zig`: pass `json_out` into the `run` dispatch.
- `src/test_e2e.zig`: add `run --json` fixtures (ok, failing, extra-args).

## 3. Acceptance Criteria

- [ ] `fmr run <repo> <cmd> --json` emits the envelope; stdout is valid JSON.
- [ ] `fmr run <repo> <failing-cmd> --json` emits `result: "failed"` and exits 4.
- [ ] Default (no `--json`) streaming behavior is unchanged.
- [ ] `zig fmt --check`, `zig build test`, `zig build test-e2e` all pass.
- [ ] `docs/gui/json-contract.md` gains a `fmr run --json` section.
