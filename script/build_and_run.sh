#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="BatChmodAS"
BUNDLE_ID="local.codex.BatChmodAS"
APP_VERSION="1.0"
APP_BUILD="1"
MIN_SYSTEM_VERSION="14.0"
ICON_FILE="BatChmod.icns"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_RESOURCES="$ROOT_DIR/Sources/BatChmodAS/Resources"
SOURCE_ICON="$ROOT_DIR/Sources/BatChmodAS/Resources/$ICON_FILE"

cd "$ROOT_DIR"

build_app() {
  local configuration="${1:-debug}"
  local swift_flags=()

  if [[ "$configuration" == "release" ]]; then
    swift_flags=(-c release)
  fi

  swift build "${swift_flags[@]}"

  local build_bin_dir
  build_bin_dir="$(swift build "${swift_flags[@]}" --show-bin-path)"
  local build_binary="$build_bin_dir/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  for localization_dir in "$SOURCE_RESOURCES"/*.lproj; do
    if [[ -d "$localization_dir" ]]; then
      cp -R "$localization_dir" "$APP_RESOURCES/"
    fi
  done

  if [[ -f "$SOURCE_ICON" ]]; then
    cp "$SOURCE_ICON" "$APP_RESOURCES/$ICON_FILE"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_FILE</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

case "$MODE" in
  --build|build)
    build_app debug
    echo "Built debug app bundle at: $APP_BUNDLE"
    ;;
  --release|release)
    build_app release
    echo "Built release $APP_NAME $APP_VERSION ($APP_BUILD) at: $APP_BUNDLE"
    ;;
  run)
    build_app debug
    open_app
    ;;
  --debug|debug)
    build_app debug
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    build_app debug
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    build_app debug
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    build_app debug
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|release|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
