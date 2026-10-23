#!/bin/bash
# Run on a Mac. No paid certificate, notarization, publishing or security changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo "This app must be built on macOS with Xcode command-line tools." >&2; exit 1; }
for tool in cargo rustup xcrun codesign ditto lipo plutil shasum; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }; done
export MACOSX_DEPLOYMENT_TARGET=13.0
SDK="$(xcrun --sdk macosx --show-sdk-path)"
export CARGO_TARGET_DIR="$ROOT/core/target"
HOST="$(rustc -vV | sed -n 's/^host: //p')"
[[ "$HOST" == *apple-darwin ]] || { echo "Use a native macOS Rust toolchain." >&2; exit 1; }
cd "$ROOT"
cargo fmt --manifest-path core/Cargo.toml -- --check
cargo clippy --manifest-path core/Cargo.toml --target "$HOST" --locked --all-targets -- -D warnings
cargo test --manifest-path core/Cargo.toml --target "$HOST" --locked
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' packaging/Info.plist)"
# Unique output: a rerun never deletes or reuses an existing bundle.
WORK="$(mktemp -d "$ROOT/build-XXXXXXXX")"
APP="$WORK/GestureLite.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/THIRD_PARTY_NOTICES.txt"
plutil -lint "$APP/Contents/Info.plist"
for ARCH in arm64 x86_64; do
  if [[ "$ARCH" == arm64 ]]; then TARGET=aarch64-apple-darwin; else TARGET=x86_64-apple-darwin; fi
  rustup target add "$TARGET"
  cargo build --manifest-path core/Cargo.toml --target "$TARGET" --release --locked
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos13.0" -sdk "$SDK" \
    -import-objc-header native/Core.h native/Models.swift native/InputMonitor.swift native/SettingsView.swift native/main.swift \
    -L "$CARGO_TARGET_DIR/$TARGET/release" -lgesturelite_mac_core \
    -framework AppKit -framework SwiftUI -framework ApplicationServices -framework CoreGraphics \
    -lresolv -liconv -o "$WORK/GestureLite-$ARCH"
done
lipo -create "$WORK/GestureLite-arm64" "$WORK/GestureLite-x86_64" -output "$APP/Contents/MacOS/GestureLite"
chmod 755 "$APP/Contents/MacOS/GestureLite"
lipo -verify_arch arm64 x86_64 "$APP/Contents/MacOS/GestureLite"
# An ad-hoc signature is free and supplies code integrity, NOT verified identity.
# It does not remove Gatekeeper's first-launch warning or provide notarization.
codesign --force --sign - --timestamp=none --identifier org.gesturelite.mac --options runtime "$APP"
codesign --verify --strict --verbose=2 "$APP"
"$APP/Contents/MacOS/GestureLite" --self-test | tee "$WORK/native-self-test.txt"
codesign --display --verbose=2 "$APP" 2> "$WORK/signature.txt"
otool -L "$APP/Contents/MacOS/GestureLite" > "$WORK/linked-libraries.txt"
if grep -E '/(Users|opt|usr/local)/' "$WORK/linked-libraries.txt"; then
  echo "Unexpected developer-machine library dependency; refusing to package." >&2; exit 1
fi
ZIP="$ROOT/dist/GestureLite-Mac-$VERSION-universal-preview.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cp "$WORK/signature.txt" "$ROOT/dist/signature.txt"
cp "$WORK/linked-libraries.txt" "$ROOT/dist/linked-libraries.txt"
cp "$WORK/native-self-test.txt" "$ROOT/dist/native-self-test.txt"
echo "Preview archive: $ZIP"
echo "Ad-hoc signed only. NOT notarized, NOT published, NOT yet hardware-validated."
echo "Build bundle retained: $APP"
