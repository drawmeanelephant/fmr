# fmr GUI Phase — Issue Review

> Review of GitHub issues **GUI-1 (#8)** through **GUI-4 (#11)** against the
> actual fmr implementation, Aug 16 2026. Ground truth for the JSON contract:
> [`docs/gui/json-contract.md`](./json-contract.md). The updated GUI-1 spec ready
> to paste back into GitHub: [`docs/gui/gui-1-spec.md`](./gui-1-spec.md).

## Status

| Issue | # | Summary | Verdict |
|---|---|---|---|
| GUI-1: Swift Package Architecture, Process Bridge, & JSON Decoders | 8 | Package scaffold, `FMRBridge`, models, `WorkspaceViewModel` | **Solid — needs corrections** (this is what you're working on) |
| GUI-2: Menu Bar Companion Popover | 9 | `MenuBarExtra`, summary banner, quick sync/rag | **Good — 3 notes** |
| GUI-3: Workspace Dashboard Window | 10 | Split view, status cards, commands runner, openers | **Blocked on data gaps in fmr JSON** |
| GUI-4: Diagnostics Sheet, Packaging & Polish | 11 | Doctor sheet, `build_app.sh`, shortcuts | **Good — 2 notes** |

---

## GUI-1 (issue #8) — review

The three-file split (`Models.swift`, `FMRBridge.swift`, `WorkspaceViewModel.swift`)
is right and matches the plan. Corrections:

1. **`RepoStatus.state` is not what the UI will mostly match on.** Verified enum:
   `ok | missing | not_repo | worktree | detached | unborn`. There is no `dirty`,
   `behind`, `ahead`, or `refused` state — a dirty repo is `state: "ok"` with
   `dirty_tracked > 0`. Compute pills from counts, not `state`.
2. **`SyncOutcome` fields are wrong as specced.** Real per-repo sync fields are
   `name / result / exit / message` (`result: ok|refused|failed|skipped`). There
   is **no** `before`/`after` SHA or `action`. `SyncSummary` exists
   (`ok/refused/failed/skipped`) but **only on sync** — status/check/rag have no
   summary, so the base response's `summary` must be optional.
3. **Doctor levels are `ok | warn | problem`**, never `error`. And doctor's
   `exit` is `1` when problems exist — that's a *healthy* "has problems" signal,
   not a crash; don't surface it as an error state.
4. **`RagOutcome`**: `status` ∈ `ok | skipped | refused | error`; `action` has
   **spaces** (`"up to date"`) — use raw-string enums. `rag --gc` emits a totally
   different shape (`command: "rag-gc"`, `pruned`, `retaining`, no `repos`).
5. **Missing `kind`, `path`, `url` on `RepoStatus`** — GUI-3 needs these. Decide
   now: small fmr change to add them to status JSON (recommended), or app parses
   `workspace.json`.
6. **Bridge must drain stdout and stderr concurrently** (pipe-buffer deadlock on
   chatty `fmr rag` exporters), use the JSON `exit` field as truth, and run
   **unsandboxed** (it spawns processes and reads `~/dev`, `~/config`).
7. `WorkspaceViewModel` methods are exactly right. Make it `@MainActor`, and
   `FMRBridge` should live in a `struct` with `async throws` funcs so Swift 6
   strict concurrency is happy (`Process` is not `Sendable` — keep it local to
   each call).

Full corrected spec: [`docs/gui/gui-1-spec.md`](./gui-1-spec.md).

## GUI-2 (issue #9) — review

- "Sync All" must be **one** `fmr sync --all --json` process — fmr parallelizes
  internally and locks per repo. Spawning one `fmr` per repo = lock contention
  and exit-code ambiguity.
- "Stale Snap (N)" pill maps to `snap == .stale`; "Behind (N)" = sum of
  `behind > 0`; "Dirty (N)" = `dirty_tracked > 0 || untracked > 0`; "Clean (N)" =
  everything else. Do this on the ViewModel, not per-row.
- `MenuBarExtra` apps should set `LSUIElement` (GUI-4 already does) — otherwise
  you get both a Dock icon and a menu bar icon. Dependency on GUI-4 is fine;
  just note it.

## GUI-3 (issue #10) — review

The feature set is great, but **three of its acceptance criteria cannot be met
with today's status JSON**:

| Need | Gap | Fix |
|---|---|---|
| Kind filters (Zig/Go/Sites/Tools) | `kind` not in `ReposStatus` | add `kind` to status JSON, or read `workspace.json` |
| Remote URL link | `url` not in status JSON | same |
| "Open in Finder/Terminal/Editor" | repo `path` not in status JSON | add `path` to status JSON |
| Custom command buttons | `commands` not exposed anywhere in JSON | new `fmr describe`/`fmr config --json`, or parse config |

**Recommendation:** extend `fmr status --json` with `kind`, `path`, and `url`
(one small `src/status.zig` change, no schema break — additive fields), and add
`fmr config --json` (or fold into status) that emits the catalog incl. per-repo
`commands` and rag mode. That keeps "the native UI never needs duplicate git
logic" true and extends it to config logic.

- Live console: use `fmr run <repo> <cmd>` raw streaming (no `--json` support
  there); forward stdout/stderr lines into the console view.
- Repo list should also surface `paused` repos (config `sync.enabled: false`).

## GUI-4 (issue #11) — review

- Doctor sheet: `level == .problem` → red, `.warn` → yellow, `.ok` → green; after
  "Fix Issues" (`fmr doctor --fix`), **re-run doctor and show fresh results** —
  `exit` reflects post-fix state.
- `build_app.sh`: also `codesign --force --deep -s - dist/Fmr.app` for local
  double-click launch (macOS refuses unsigned GUI binaries on Apple Silicon), and
  remember the `Contents/Helpers/fmr` path is what the GUI-1 locator should check
  **first** (before `./zig-out/bin/fmr`).
- Shortcuts are straightforward `keyboardShortcut` modifiers; `Cmd+S` conflicts
  with the system Save convention only if a text field is focused — acceptable.

## fmr-side follow-ups — status

1. ✅ **Done** — `kind`, `path`, `url` added to `ReposStatus` JSON (unblocks
   GUI-3's kind filters, URL links, and Finder/Terminal openers).
2. ✅ **Done** — `before`/`after`/`action` added to sync per-repo JSON (enables
   "`1234abc → 5678def (fast-forward)`" rows). `action` carries the refusal tag
   (`dirty`, `ahead`, `diverged`, ...) or `clone`/`fast-forward`/`noop`/`skip`.
3. ✅ **Done** — new `fmr config --json` command emitting the catalog (paths,
   parallelism, and per-repo kind/path/url/check/rag/commands) so the app never
   parses `workspace.json` itself.
4. ☐ **Open** — a `--json` variant for `fmr run` (GUI-3 console wants structured
   completion events), or leave run streaming and wrap it.

All three completed changes are additive (no field removed, no shape broken) and
covered by the e2e suite. See [`json-contract.md`](./json-contract.md) for the
updated shapes.
