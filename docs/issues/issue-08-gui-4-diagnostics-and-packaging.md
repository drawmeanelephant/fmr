# Issue 8: Diagnostics Sheet, App Packaging (`scripts/build_app.sh`), & Polish

**Slice**: GUI-4 (Diagnostics, Packaging, & Polish)  
**Parent Plan**: [`implementation_plan.md`](../../implementation_plan.md)  
**Depends On**: GUI-1 (Issue #5), GUI-2 (Issue #6), GUI-3 (Issue #7)

---

## 1. Goal & Context

Add the offline diagnostic inspector sheet (`fmr doctor` with 1-click `--fix`), build automation script to package `Fmr.app`, and finish UI polish (keyboard shortcuts, dark/light mode accents, and auto-refresh timer).

---

## 2. Technical Specification

### Files to Create / Modify
- [`app/Sources/FmrApp/Views/DoctorSheetView.swift`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/app/Sources/FmrApp/Views/DoctorSheetView.swift):
  - Diagnostic summary header (Problems count, Warnings count).
  - List of check rows with level indicators (green check, yellow warning, red error).
  - 1-click **Fix Issues (`fmr doctor --fix`)** button to clear stale locks and staging dirs.
- [`scripts/build_app.sh`](file:///Users/tbuddy/Documents/antigravity/fuckmerunning/scripts/build_app.sh):
  - Builds `fmr` core binary via `zig build -Doptimize=ReleaseFast`.
  - Builds Swift App executable via `swift build -c release --package-path app`.
  - Creates `dist/Fmr.app/Contents/{MacOS,Resources,Helpers}` bundle.
  - Generates `Info.plist` with `LSUIElement` / bundle metadata.
  - Copies `fmr` binary into `Contents/Helpers/fmr`.
- Polish & Shortcuts:
  - `Cmd+R`: Refresh workspace status.
  - `Cmd+S`: Sync all clean repositories.
  - `Cmd+D`: Open Doctor diagnostics.

---

## 3. Acceptance Criteria

- [ ] Doctor sheet opens and displays all system checks.
- [ ] Clicking "Fix Stale Issues" runs `fmr doctor --fix` and re-runs checks automatically.
- [ ] Running `bash scripts/build_app.sh` creates a valid `dist/Fmr.app` bundle.
- [ ] Double-clicking `dist/Fmr.app` launches the native macOS app with the embedded `fmr` engine.
