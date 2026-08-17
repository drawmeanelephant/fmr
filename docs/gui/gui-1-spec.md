# GUI-1 (rev. 2): Swift Package Architecture, Process Bridge, & JSON Decoders

**Slice**: GUI-1 (Core Swift Foundation)
**Parent Plan**: [`docs/gui/README.md`](./README.md), JSON contract: [`docs/gui/json-contract.md`](./json-contract.md)
**Task spec**: [`docs/issues/issue-05-gui-1-swift-bridge-and-models.md`](../issues/issue-05-gui-1-swift-bridge-and-models.md) (on conflict, the issue spec wins)
**Depends On**: fmr `--json` (all commands emit it — verified)

> Revision 2 corrects the model shapes against the *implemented* fmr JSON
> contract (see `docs/gui/json-contract.md`). Differences from rev. 1 are marked
> **[CHANGED]**.

## 1. Goal & Context

Establish the Swift / SwiftUI application scaffolding for macOS 14+
(`app/Package.swift`) and the asynchronous process bridge that talks to the fmr
core via `--json`. The native UI must never duplicate git logic — it consumes
typed models emitted by fmr.

## 2. Technical Specification

### Files to Create

#### `app/Package.swift`

Swift 6 package, `.macOS(.v14)`, executable target `FmrApp`. No third-party
dependencies (AppKit/SwiftUI/Foundation only).

#### `app/Sources/FmrApp/Models.swift`

Decode with `JSONDecoder`, `keyDecodingStrategy = .convertFromSnakeCase`.
Decode all enums from raw `String` with an `unknown` fallback case so future fmr
states never crash the app.

```swift
// Envelope shared by all commands. `summary` is optional — only `sync` emits it.
struct FmrResponse<Item: Decodable>: Decodable {
    let version: Int
    let command: String
    let exit: Int
    let repos: [Item]?
    let summary: SyncSummary?
    // doctor-only fields:
    let problems: Int?
    let warnings: Int?
    let checks: [DoctorCheck]?
}

// ── fmr status ──────────────────────────────────────────────────────────────
struct StatusResponse: Decodable { let repos: [RepoStatus] }

struct RepoStatus: Decodable {
    let name: String
    let branch: String
    let head: String
    let state: RepoState
    let paused: Bool
    let ahead: Int
    let behind: Int
    let dirtyTracked: Int
    let untracked: Int
    let snap: SnapState
    let sessions: Int
}

// [CHANGED] verified enum — there is NO dirty/behind/ahead/refused state.
// Dirty/behind are conveyed via counts; the UI derives pills from counts.
enum RepoState: String, Decodable { case ok, missing, notRepo = "not_repo",
    worktree, detached, unborn, unknown }

enum SnapState: String, Decodable { case ok, stale, none, unknown }

// ── fmr sync ────────────────────────────────────────────────────────────────
struct SyncResponse: Decodable { let repos: [SyncOutcome]; let summary: SyncSummary }

// [CHANGED] real fields are name/result/exit/message — no before/after/action.
struct SyncOutcome: Decodable {
    let name: String
    let result: SyncResult
    let exit: Int
    let message: String
}
enum SyncResult: String, Decodable { case ok, refused, failed, skipped, unknown }

struct SyncSummary: Decodable { let ok: Int; let refused: Int
    let failed: Int; let skipped: Int }

// ── fmr doctor ──────────────────────────────────────────────────────────────
// [CHANGED] levels are ok|warn|problem — there is no `error`.
struct DoctorResponse: Decodable { let problems: Int; let warnings: Int
    let checks: [DoctorCheck] }
struct DoctorCheck: Decodable { let level: DoctorLevel; let message: String }
enum DoctorLevel: String, Decodable { case ok, warn, problem, unknown }

// ── fmr check ───────────────────────────────────────────────────────────────
struct CheckResponse: Decodable { let repos: [CheckOutcome] }
struct CheckOutcome: Decodable { let name: String; let status: CheckStatus
    let exit: Int; let message: String }
enum CheckStatus: String, Decodable { case ok, failed, skipped, unknown }

// ── fmr rag ─────────────────────────────────────────────────────────────────
struct RagResponse: Decodable { let repos: [RagOutcome] }
struct RagOutcome: Decodable { let name: String; let status: RagStatus
    let action: RagAction; let sha: String; let exit: Int; let message: String }
enum RagStatus: String, Decodable { case ok, skipped, refused, error, unknown }
// [CHANGED] action strings contain spaces — raw-value enum:
enum RagAction: String, Decodable { case snap, upToDate = "up to date", skip,
    missing, notRepo = "not_repo", worktree, unborn, dirty, none, unknown }

// rag --gc emits a DIFFERENT envelope (command: "rag-gc", no repos array):
struct RagGCResponse: Decodable { let pruned: Int; let retaining: Int }
```

#### `app/Sources/FmrApp/FMRBridge.swift`

- **Binary locator**, in priority order:
  1. `Bundle.main.bundleURL/Contents/Helpers/fmr` (packaged app — GUI-4)
  2. `./zig-out/bin/fmr` relative to cwd (dev mode)
  3. `~/.local/bin/fmr`
  4. `PATH`
- **Async runner**: `func run(_ args: [String]) async throws -> Data` spawning
  `Process` with `Pipe`s, **draining stdout and stderr concurrently**
  (`FileHandle.readabilityHandler` on both — otherwise a chatty `fmr rag`
  exporter fills the 64 KB pipe buffer and deadlocks the child). Encode stderr
  into the thrown error for debugging.
- **Typed entry points**, each `fmr <cmd> <repos...> --json` and decoding the
  matching response; the `exit` field in JSON is the source of truth:
  `status()`, `sync(repos:)`, `syncAll()`, `doctor(fix:)`, `check(repos:)`,
  `rag(repos:force:)`.
- Keep `Process` instances local to each call (not `Sendable` — don't store them).
- Run unsandboxed (no App Sandbox entitlement): the app spawns processes and
  reads `~/dev`, `~/Code`, `~/config`.

#### `app/Sources/FmrApp/WorkspaceViewModel.swift`

`@MainActor @Observable final class WorkspaceViewModel`:

- State: `var repos: [RepoStatus]`, `var isRefreshing: Bool`,
  `var activeTask: String?`, `var lastUpdated: Date?`, plus per-action results
  (last sync/rag/doctor outcome) for the menu bar and dashboard.
- Methods: `refreshStatus()`, `syncAll()`, `syncRepo(name:)`,
  `runDoctor(fix:)`, `ragRepo(name:force:)` — all `async throws`, updating
  `repos` reactively after each completes.
- Derived helpers the views need (computed from counts, per JSON contract):
  `isDirty`, `isBehind`, `isClean`, `staleSnapCount`, `behindCount`,
  `dirtyCount`.

## 3. Acceptance Criteria

- [ ] `swift build --package-path app` compiles cleanly with zero warnings
      (Swift 6 strict concurrency mode).
- [ ] `FMRBridge` locates the built binary and runs `fmr status --json`
      successfully from a temp config.
- [ ] Models decode **real** `fmr status --json` output — including a dirty repo
      (`dirty_tracked > 0` with `state: "ok"`) and a repo with `snap: "stale"`.
- [ ] `WorkspaceViewModel.refreshStatus()` populates `repos` and the UI updates
      reactively.
- [ ] Spawning `fmr rag` with a chatty exporter does not deadlock (pipe draining
      verified).
- [ ] Unknown future enum values decode as `.unknown` without throwing.
