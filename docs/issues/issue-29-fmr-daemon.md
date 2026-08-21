# Issue 29: `fmr daemon` — Optional Launchd Auto-Sync (M2 — Personal)

**Milestone**: M2 v0.3 Personal (`docs/MILESTONES.md`)  
**Area**: Core CLI (Zig) + Infra  
**Size**: S (1–2h)  
**Depends On**: #22

---

## 1. Goal & Context

T3 runs a fleet daemon by default — you don’t want that. But you *do* want “my primaries are fresh when I sit down” without remembering `fmr sync --all` every morning. The local answer: an **opt-in** launchd agent that runs `fmr sync --all --json` every 10m, only when you’re on Wi-Fi / not on battery? v1 is simpler: just periodic, opt-in, with a menubar badge.

No background process, no watch mode — launchd *is* the daemon.

## 2. CLI Signature

```
fmr daemon install [--interval <duration>] [--config <path>]  # duration: 5m|10m|30m|1h default 10m
fmr daemon uninstall
fmr daemon status [--json]   # shows installed?, interval, last run, next run, last summary
fmr daemon run               # one-shot run used by launchd (internal) — runs sync --all, writes last-run log
```

- `install` writes `~/Library/LaunchAgents/com.drawmeanelephant.fmr.sync.plist`, loads it (`launchctl bootstrap`), writes `~/.fmr/daemon.json` with interval/config.
- `uninstall` unloads and removes plist.
- `status` reads `daemon.json` + `launchctl print` or plist existence.
- `run` is what launchd execs: `fmr sync --all --json` → append to `~/.fmr/daemon.log`, update `daemon.json` last summary.

## 3. Technical Specification

- `src/daemon.zig` *(new, ~200 lines)* — plist generation (XML string), `launchctl` spawn via `process.run`, file I/O for `daemon.json`/`daemon.log`. No `std.posix` daemonize — launchd owns lifecycle.
- `src/main.zig` — dispatch `daemon` subcommand with sub-subcommands.
- `app/Sources/FmrApp/WorkspaceViewModel.swift` — optional: menu bar `AppDelegate` or ViewModel polls `fmr daemon status --json` and shows badge “last sync: 7m ago, 1 refused”.
- `scripts/install_daemon.sh` alternative is just `fmr daemon install` — no separate script.

### Plist shape (v1)

```xml
<key>Label</key><string>com.drawmeanelephant.fmr.sync</string>
<key>ProgramArguments</key><array><string>/opt/homebrew/bin/fmr</string><string>daemon</string><string>run</string></array>
<key>StartInterval</key><integer>600</integer>
<key>RunAtLoad</key><false/>
```

Resolve `fmr` path via `FMRBridge`-style lookup at install time and bake it in.

## 4. Acceptance Criteria

- [ ] `fmr daemon install --interval 5m` creates `~/Library/LaunchAgents/com.drawmeanelephant.fmr.sync.plist` with `StartInterval 300`.
- [ ] `fmr daemon status` prints `installed: true, interval: 5m, last: <timestamp>, summary: ok 12 refused 1`.
- [ ] `fmr daemon uninstall` removes plist and unloads via launchctl (mock launchctl in tests with `PATH` stub).
- [ ] `launchctl bootstrap` failure is reported with `exit 1` and message (no silent swallow).
- [ ] `zig build test && zig build test-e2e` green (daemon install/status/uninstall in temp HOME).
