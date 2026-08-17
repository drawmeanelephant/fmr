# Issue 18: Infra — Build & Test the Swift App in CI

**Area**: CI / GitHub Actions  \
**Parent Plan**: [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md)  \
**Depends On**: None

---

## 1. Goal & Context

`.github/workflows/ci.yml` builds and tests the Zig core (fmt, `zig build`,
`zig build test`, `zig build test-e2e`) on `ubuntu-latest` and `macos-latest`,
but the Swift GUI (`app/`) is **not covered**: a regression in `Models.swift`,
`FMRBridge.swift`, or the views would merge undetected. This issue adds a Swift
job (or extends the existing one) so the GUI compiles and its unit tests run on
every push/PR.

## 2. Technical Specification

### Workflow changes

Add a `gui` job to `.github/workflows/ci.yml`:

- `runs-on: macos-latest` (SwiftUI requires macOS; the Zig job keeps covering
  Linux).
- Steps:
  1. `actions/checkout@v4`
  2. Setup Zig (same `mlugg/setup-zig@v2`, `0.16.0`) — needed because
     `swift test` fixtures and the app's `--json` contract tests may invoke the
     real binary; at minimum build `zig-out/bin/fmr` so `FMRBridge` tests can
     resolve a binary.
  3. `zig build`
  4. `swift build --package-path app`
  5. `swift test --package-path app`
- Keep the existing Zig matrix job unchanged.

### Files to touch

- `.github/workflows/ci.yml`

## 3. Acceptance Criteria

- [ ] Pushing to `main` / opening a PR runs a macOS job that compiles the Swift app.
- [ ] `swift test --package-path app` runs in CI (all 4+ GUI unit tests).
- [ ] The Zig matrix (Linux + macOS) still runs and passes.
- [ ] A deliberately broken `Models.swift` fails the `gui` job (verified once by
      the author before merging).
