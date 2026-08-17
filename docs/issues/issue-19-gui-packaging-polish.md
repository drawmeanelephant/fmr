# Issue 19: Packaging — `build_app.sh` LSUIElement, Codesigning, & Versioning

**Area**: GUI / Packaging  \
**Parent Plan**: [`docs/gui/README.md`](../gui/README.md)  \
**Depends On**: None

---

## 1. Goal & Context

`scripts/build_app.sh` builds the Zig core + Release Swift app and assembles
`dist/Fmr.app`. Three gaps remain before the bundle is a pleasant daily driver:

1. **`LSUIElement` is `false`** in the generated `Info.plist`, but this is a
   `MenuBarExtra` app — with a Dock icon *and* a menu bar icon it feels like two
   apps. The menu-bar companion (GUI-2) is the primary surface.
2. **No codesigning step.** macOS on Apple Silicon refuses to launch unsigned
   GUI binaries; a local ad-hoc signature (`codesign --force --deep -s -`) is
   needed so `open dist/Fmr.app` works after every build.
3. **No versioning.** `CFBundleShortVersionString` is hardcoded to `1.0.0`; the
   bundle should carry the core's version so the GUI can display it.

## 2. Technical Specification

### `scripts/build_app.sh` changes

- Set `LSUIElement` to `<true/>` (menu-bar-only app; no Dock icon). Note: the
  dashboard window is still reachable from the menu bar popover.
- After assembling the bundle, run:
  ```bash
  codesign --force --deep --sign - "$APP_BUNDLE"
  ```
  (ad-hoc signature; fine for local use — document that a Developer ID is the
  path for distribution).
- Add an `fmr` version source:
  - Add `--version` to the core CLI (or read `git describe`), and embed it in
    `CFBundleShortVersionString` / `CFBundleVersion` and a `FMRCoreVersion`
    plist key the About panel can read.
- Verify the bundle with `codesign --verify --deep --strict` and
  `spctl --assess` (note: ad-hoc fails `spctl` by design; gate on `codesign
  --verify` only).

### Files to touch

- `scripts/build_app.sh`
- `src/main.zig` (add `--version` if not present)
- `app/Sources/FmrApp/FmrApp.swift` or a small About view (display version)

## 3. Acceptance Criteria

- [ ] `bash scripts/build_app.sh` produces `dist/Fmr.app` with `LSUIElement=true`.
- [ ] `open dist/Fmr.app` launches and shows only the menu bar icon (no Dock icon).
- [ ] `codesign --verify --deep --strict dist/Fmr.app` passes.
- [ ] The About/menu shows the core version, sourced from `fmr --version`.
- [ ] `swift build --package-path app` and `zig build` still pass.
