# Mac preview validation — October 22, 2026

This is source implementation plus portable-core verification, not a certified or runtime-tested Mac release.

## Completed on the Windows development machine

- Independent Rust formatting passed.
- Independent Rust Clippy, all targets, with warnings denied passed.
- Independent Rust tests passed: 15 tests, zero failures. Includes 10,000 tap-then-hold sequences, cardinal distance thresholds, diagonal dominance, click/gesture exclusivity, keyboard repeat/passthrough, simultaneous-hold burst prevention, reset/disable/config replacement, exact replay markers, malformed/duplicate configuration and C ABI lifetime/layout checks. Local execution evidence: `verification/core-tests.txt`.
- Independent Rust release build passed. The resulting Windows-target library is a test/build output, not a Mac library or installer; it is excluded from the source archive.
- All four native Swift files passed Tree-sitter Swift syntax parsing. This checks grammar only, not Apple SDK symbols, Swift type checking, linking, availability or UI layout. Parser tools are confined to the ignored verification folder and are not shipped in the app.
- Info.plist parsed and checked for menu-bar app mode, executable name and macOS 13 minimum. Example JSON parsed. Workflow YAML parsed and checked for read-only permissions, explicit ARM/Intel runners and absence of a publishing action.
- Bash build-script syntax passed. The unprivileged Git Bash invocation once failed on a sandbox named-object permission; the same read-only syntax check passed with normal process permissions. No security policy was changed.
- No Mac compiler, SDK, notarization, signature or packaged app was run/created on this Windows machine. No GitHub repository, release or remote job was created.

## Still required on macOS

- Compile and type-check the AppKit/SwiftUI and Core Graphics code against a real SDK, link both architectures, verify ad-hoc signatures and run the included native Swift/C/Rust self-test. The build script and CI workflow are prepared but have not run on a Mac.
- Test real mouse button numbering, keyboard layouts, permissions, self-event filtering, key releases, raw tap behavior, Spaces shortcuts, session changes and Gatekeeper first launch/update behavior. See MANUAL_TESTS.md.
- Measure memory/CPU/size. No Mac performance numbers or glitch-free claim is made.
- Choose a project license/distribution policy before public release. GitHub publishing and Mac App Store submission have not been performed.

## Windows preservation

Only the new `macos/` project was written. The existing Windows files and original Store MSIX were fingerprinted before work. The final preservation check compares all 77 recorded files; its local report is in `verification/windows-preservation.json` and is intentionally excluded from public/source archives. No Windows app was stopped, restarted, upgraded, reconfigured or repackaged during this task.

The original Windows code is not a dependency of this project. Its Cargo files, source, scripts, assets, documentation and Store artifact must remain unchanged. Public Mac builds will use this directory as their independent repository root.
