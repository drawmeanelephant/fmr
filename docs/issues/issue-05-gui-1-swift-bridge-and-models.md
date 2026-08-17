# Issue 5: Swift Package Architecture, Process Bridge, & JSON Decoders

**Slice**: GUI-1 (Core Swift Foundation)  
**Parent Plan**: [`docs/gui/README.md`](../../docs/gui/README.md)  
**Depends On**: Slice 4 (`fmr --json`)

> **Design reference**: the revised spec with corrected Swift models lives in
> [`docs/gui/gui-1-spec.md`](../../docs/gui/gui-1-spec.md); the authoritative JSON
> shapes are in [`docs/gui/json-contract.md`](../../docs/gui/json-contract.md).
> On conflict, the issue spec (this file) wins.

---

## 1. Goal & Context

Establish the Swift / SwiftUI application scaffolding for macOS 14+ (`app/Package.swift`) and create the asynchronous process execution bridge that communicates with the `fmr` core engine via `--json`.

This layer ensures the native UI never needs duplicate git logic, directly consuming typed models emitted by `fmr`.

---

## 2. Technical Specification

### Files to Create
- [`app/Package.swift`](../../app/Package.swift): Swift 6 package targeting `.macOS(.v14)`, defining executable target `FmrApp`.
- [`app/Sources/FmrApp/Models.swift`](../../app/Sources/FmrApp/Models.swift): Codable Swift models:
  - `StatusResponse`, `RepoStatus` (fields: `name`, `branch`, `head`, `state`, `paused`, `ahead`, `behind`, `dirty_tracked`, `untracked`, `snap`, `sessions`).
  - `SyncResponse`, `SyncOutcome`, `SyncSummary`.
  - `DoctorResponse`, `DoctorCheck` (`level`, `message`).
  - `CheckResponse`, `CheckOutcome`.
  - `RagResponse`, `RagOutcome`.
- [`app/Sources/FmrApp/FMRBridge.swift`](../../app/Sources/FmrApp/FMRBridge.swift):
  - Binary locator: checks `./zig-out/bin/fmr`, `~/.local/bin/fmr`, `PATH`, or bundle path.
  - Async runner: executes `fmr <subcommand> --json` via `Process` + `Pipe`.
  - Decodes JSON outputs into Swift types and captures live stdout/stderr streams.
- [`app/Sources/FmrApp/WorkspaceViewModel.swift`](../../app/Sources/FmrApp/WorkspaceViewModel.swift):
  - `@Observable` state container holding `repos: [RepoStatus]`, `isRefreshing: Bool`, `activeTask: String?`, and `lastUpdated: Date?`.
  - Methods for `refreshStatus()`, `syncAll()`, `syncRepo(name: String)`, `runDoctor(fix: Bool)`, `ragRepo(name: String, force: Bool)`.

---

## 3. Acceptance Criteria

- [ ] `swift build --package-path app` compiles cleanly with zero warnings.
- [ ] `FMRBridge` successfully locates the `fmr` binary and executes `fmr status --json`.
- [ ] Models decode real `fmr status --json` output into typed structs.
- [ ] `WorkspaceViewModel.refreshStatus()` updates repository lists reactively.
