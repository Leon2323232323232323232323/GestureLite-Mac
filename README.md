# GestureLite for Mac — independent 0.1.0 preview project

A native menu-bar gesture utility for macOS 13 or later. This is a **separate implementation**, independent of the existing Windows application.

**Download:** [GestureLite Mac 0.1.0 Preview 2](https://github.com/Leon2323232323232323232323/GestureLite-Mac/releases/tag/v0.1.0-preview.2). Choose `GestureLite-Mac-0.1.0-universal-preview.zip` under Assets. It contains GestureLite.app for Apple Silicon and Intel. Both native Mac CI builds, 15 Rust tests per host, signature checks and native bridge self-tests passed. This remains an early preview: real mouse behavior, UI and first-launch permissions still need physical Mac testing. See [VALIDATION.md](VALIDATION.md).

## Implemented in source

- Native AppKit menu bar and a simple SwiftUI settings window; no Electron, browser engine, external UI framework, network service or driver.
- Distance-only cardinal gestures, one action per press, immediate recognition while held, no timer or stationary repeats. Default distance: **360 screen-coordinate points**, adjustable independently of Windows settings. Retina points are not physical pixels.
- Optional click shortcut on release when no gesture completed; otherwise normal tap passthrough if selected. A completed direction consumes the click, including an unmapped direction.
- Extra mouse buttons and F13–F20 keyboard triggers. Raw Mouse3 means Quartz button 2 (usually middle), Mouse4/5 usually Back/Forward. Device drivers can map them differently. F21–F24 are not claimed on Mac.
- Mac shortcuts using CMD, CTRL, OPT/ALT and SHIFT. Output uses physical Mac virtual-key positions; start testing with a US keyboard layout.
- Exact filtering of full and zero-extended lower-DWORD own-event markers. No unbounded action queue, delayed clicks, repeat timer or automatic hook repair.
- Shortcut output pre-creates a complete target-key down/up pair with modifier flags, without synthetic modifier key-downs. Input posting has no macOS delivery acknowledgement; actual target behavior must be tested.
- Per-user JSON at `~/Library/Application Support/GestureLite/config.json`; atomic saves, backups, invalid-draft validation and external-edit conflict checks. Operational errors only in `gesturelite.log`; no typing logs, telemetry or pointer-history logs.
- Starts **disabled every launch**, even if JSON contains a previous enabled state. Enable explicitly after applying settings and permissions. No launch-at-login feature yet.
- Fail closed if macOS disables the event tap or the session sleeps/deactivates. It does not silently resume an old hold. Release triggers before enabling again.

Use one trigger at a time in this first preview. If simultaneous holds cross thresholds on one motion event, at most the first configured action is dispatched; the other recognized holds are consumed to avoid delayed or burst actions. This is a known preview limitation, not a promise of Windows behavior parity.

## Build on a Mac

Install Apple's Xcode command-line tools and [Rust via rustup](https://rustup.rs/). No paid Apple account, Developer ID certificate or notarization credentials are used. Build from a normal user account:

```bash
bash scripts/build.sh
```

The script runs Rust formatting, Clippy and tests, builds the engine and Swift interface separately for Apple Silicon and Intel, combines a universal executable, creates a `.app`, applies a **free ad-hoc signature**, verifies it, and runs a native Swift/C/Rust bridge self-test that sends no input events. It checks linked libraries and emits:

```text
dist/GestureLite-Mac-0.1.0-universal-preview.zip
dist/GestureLite-Mac-0.1.0-universal-preview.zip.sha256
dist/signature.txt
dist/linked-libraries.txt
dist/native-self-test.txt
```

The script retains a uniquely named `build-*/GestureLite.app` folder. A build failure stops packaging. Both architecture builds and the host self-test must pass; the opposite architecture still requires its own runtime test. No installer is created by a Windows build of the portable engine.

## GitHub preparation

Use **this folder's contents as the root of a separate repository** (for example, `GestureLite-Mac`), including `.github` and `.gitignore`. The workflow will not run while it is nested inside a Windows repository. Do not upload Windows files or the ignored `verification`, `core/target`, `dist` or `build-*` folders.

The supplied workflow builds on standard `macos-15` and `macos-15-intel` runners, runs the native bridge self-test and uploads temporary build artifacts. Build jobs have read-only repository permissions; a separate release job has contents-write permission and publishes a clearly labelled GitHub prerelease only after both Mac build jobs pass on main. Pull requests only build/test; they cannot publish. It does not sign with a paid identity or notarize. No Apple secrets are needed. Standard hosted runner execution in public repositories is currently free; private-repository allowances and artifact/storage limits depend on your GitHub plan. [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

The separate public repository is [GestureLite-Mac](https://github.com/Leon2323232323232323232323/GestureLite-Mac). The initial source ZIP and checksum were uploaded through the owner's browser; the workflow imported its reviewed files once. Future builds use the browsable source tree directly. The root bootstrap ZIP is an initial snapshot; use the source at the release tag for the exact released version.

Before calling this stable, complete [MANUAL_TESTS.md](MANUAL_TESTS.md). No open-source license has been selected; source visibility and free downloads do not automatically grant an open-source license. Dependency notices are included in the app.

## First launch without paid Apple signing

To install the preview:

1. Download the preview ZIP from the project's official release and verify its SHA256 against the published checksum.
2. Extract it and move `GestureLite.app` to Applications before granting permissions. Keep the bundle identifier and installation location stable.
3. macOS may block its first launch because it is not Developer-ID-signed or notarized. If you trust the source and your Mac allows it, use the app-specific **Open Anyway** option in Privacy & Security. Managed Macs may prevent this. Do not disable Gatekeeper, SIP or other protections globally, and do not strip quarantine attributes as an installation step. [Apple guidance](https://support.apple.com/en-ie/102445)
4. Open Settings, choose **Request Permissions**, and allow the Accessibility/Input Monitoring permissions requested by macOS. These are per-app permissions, not Apple Developer Program enrollment. [Accessibility](https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac), [input monitoring](https://support.apple.com/en-euro/guide/mac-help/mchl4cedafb6/27/mac/27)
5. Configure the trigger and shortcuts, choose **Save and Apply**, then enable gestures. Close Settings to leave the menu-bar utility running; quit from its menu to stop it.

Ad-hoc signing supplies basic code integrity, not a verified developer identity or Apple malware notarization. Updates may require approval/permissions again. This workflow must be tested on the supported macOS versions before promising an easy installation experience.

Control+Left/Right/Up/Down use the Mac's configured Mission Control shortcuts; users may need to enable/change those shortcuts. Nothing can switch beyond the first/last existing desktop. An animation for an already-posted shortcut can finish after release. No private Spaces API or trackpad gesture emulation is used.

## Uninstall

Quit GestureLite from its menu bar, remove the app, and remove its per-app Privacy & Security permissions if desired. Settings and logs remain in `~/Library/Application Support/GestureLite`; remove that folder manually only if you want to erase them. There is no background service, launch agent, driver, paid certificate or system-wide security change to undo.

## Developer checks on Windows/Linux

The engine is independent of Apple frameworks:

```text
cargo fmt --manifest-path core/Cargo.toml -- --check
cargo clippy --manifest-path core/Cargo.toml --locked --all-targets -- -D warnings
cargo test --manifest-path core/Cargo.toml --locked
cargo build --manifest-path core/Cargo.toml --release --locked
```

When run from the existing Windows workspace, Cargo can inherit its Windows target setting; the Mac build script explicitly selects its native/cross Mac targets. No source dependency points into the Windows application. `scripts/source-archive.py` creates a source-only handoff ZIP; it does not create a Mac app.

Apple API references: [event taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)), [post-event access](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess()), [event-source marker](https://developer.apple.com/documentation/coregraphics/cgeventfield/eventsourceuserdata).
