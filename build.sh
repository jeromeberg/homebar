#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" "$@"
bin_path=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache" "$@")
app="$PWD/.build/HomeBar.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Frameworks"
cp "$bin_path/HomeBar" "$app/Contents/MacOS/HomeBar"
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$bin_path/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$app/Contents/Info.plist"
fi
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
