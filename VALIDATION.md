# Mac preview validation — October 22, 2026

This is a compiled Mac preview, not a certified or physically tested stable release.

## Completed on GitHub's Mac runners

[Successful workflow run](https://github.com/Leon2323232323232323232323/GestureLite-Mac/actions/runs/39885072633), source commit `1233ca081dbd70b4ee95a83dcbf6111a97f614a0`, release `v0.1.0-preview.2`:

- Both macos-15 (Apple Silicon) and macos-15-intel jobs passed.
- Rust formatting, Clippy with warnings denied, and all 15 tests passed on each host.
- Native Swift/AppKit/SwiftUI code compiled and linked for arm64 and x86_64 on each host; universal-binary architecture validation passed.
- Ad-hoc signing and strict signature verification passed. The actual universal app's Swift/C/Rust bridge self-test ran successfully on both native host architectures without posting input or requesting permissions.
- Bundle plist and linked-library checks passed. The downloaded release ZIP checksum was verified independently on Windows.
- ZIP: 1,454,168 bytes. SHA256: `bb43972d1d885f60ff5be0bab2adef2ee9e42f53d9acf1538b908d9fc34644bb`.
- First CI run exposed an incorrect lipo argument order; corrected before this release. The library audit was also restricted to dependency entries so its own absolute executable heading is not mistaken for an external library.
- GitHub reported Node 20 action deprecation warnings, with the actions automatically running on Node 24. These did not fail the builds.

## Completed on the Windows development machine

- Independent Rust formatting passed.
- Independent Rust Clippy, all targets, with warnings denied passed.
- Independent Rust tests passed: 15 tests, zero failures. Includes 10,000 tap-then-hold sequences, cardinal distance thresholds, diagonal dominance, click/gesture exclusivity, keyboard repeat/passthrough, simultaneous-hold burst prevention, reset/disable/config replacement, exact replay markers, malformed/duplicate configuration and C ABI lifetime/layout checks. Local execution evidence: `verification/core-tests.txt`.
- Independent Rust release build passed. The resulting Windows-target library is a test/build output, not a Mac library or installer; it is excluded from the source archive.
- All four native Swift files passed Tree-sitter Swift syntax parsing. This checks grammar only, not Apple SDK symbols, Swift type checking, linking, availability or UI layout. Parser tools are confined to the ignored verification folder and are not shipped in the app.
- Info.plist parsed and checked for menu-bar app mode, executable name and macOS 13 minimum. Example JSON and workflow YAML parsed. Build jobs have read-only repository permissions; the source-import and prerelease jobs have repository contents-write permission.
- Bash build-script syntax passed. The unprivileged Git Bash invocation once failed on a sandbox named-object permission; the same read-only syntax check passed with normal process permissions. No security policy was changed.
- No Mac compiler or SDK was run on this Windows machine. Mac builds and free ad-hoc signing ran on GitHub's Mac runners. No paid certificate, notarization or global security change was used.

## Still required on macOS

- Test real mouse button numbering, keyboard layouts, permissions, self-event filtering, key releases, raw tap behavior, Spaces shortcuts, session changes and Gatekeeper first launch/update behavior. See MANUAL_TESTS.md.
- Measure memory/CPU/size. No Mac performance numbers or glitch-free claim is made.
- Choose an open-source license if redistribution/modification rights are intended. This preview is publicly downloadable, but no project open-source license is assigned. No Mac App Store submission has been performed.

## Windows preservation

Only the new `macos/` project was written. The existing Windows files and original Store MSIX were fingerprinted before work. The final preservation check compares all 77 recorded files; its local report is in `verification/windows-preservation.json` and is intentionally excluded from public/source archives. No Windows app was stopped, restarted, upgraded, reconfigured or repackaged during this task.

The original Windows code is not a dependency of this project. Its Cargo files, source, scripts, assets, documentation and Store artifact must remain unchanged. Public Mac builds will use this directory as their independent repository root.
