#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/phoenix-optimization/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/phoenix-optimization/swift-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"
scratch="$(mktemp -d /tmp/phoenix-store-smoke.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
if [[ -n "${PHOENIX_CORE_BUILD_DIR:-}" ]]; then
    core_args=(-I "$PHOENIX_CORE_BUILD_DIR/Modules" "$PHOENIX_CORE_BUILD_DIR"/PhoenixValleyCore.build/*.o)
else
    swiftc -swift-version 6 -module-name PhoenixValleyCore -emit-module -emit-library \
        -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
        Sources/PhoenixValleyCore/*.swift -o "$scratch/libPhoenixValleyCore.dylib" \
        -emit-module-path "$scratch/PhoenixValleyCore.swiftmodule"
    core_args=(-I "$scratch" -L "$scratch" -lPhoenixValleyCore -Xlinker -rpath -Xlinker "$scratch")
fi
swiftc -swift-version 6 "${core_args[@]}" \
    -module-cache-path "$SWIFTPM_MODULECACHE_OVERRIDE" \
    PhoenixValleyApp/Persistence/ProjectFileStore.swift \
    PhoenixValleyApp/Features/RoadDocumentStore.swift \
    Tests/PhoenixValleyStoreSmoke/main.swift -o "$scratch/store-smoke"
"$scratch/store-smoke" "$scratch"
