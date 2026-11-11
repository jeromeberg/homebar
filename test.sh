#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
developer_dir=$(xcode-select -p)
frameworks="$developer_dir/Library/Developer/Frameworks"
if [ -d "$frameworks/Testing.framework" ]; then
    swift test --disable-sandbox --cache-path "$PWD/.build/cache" \
        -Xswiftc -F -Xswiftc "$frameworks" \
        -Xlinker -rpath -Xlinker "$frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib" "$@"
else
    swift test --disable-sandbox --cache-path "$PWD/.build/cache" "$@"
fi
