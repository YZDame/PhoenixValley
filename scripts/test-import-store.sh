#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="$(mktemp -d /tmp/phoenix-import-store.XXXXXX)"
trap 'rm -rf "$scratch"' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$scratch/clang-cache}"
if [[ -n "${PHOENIX_CORE_BUILD_DIR:-}" ]]; then
    core_args=(-I "$PHOENIX_CORE_BUILD_DIR/Modules" "$PHOENIX_CORE_BUILD_DIR"/PhoenixValleyCore.build/*.o)
else
    swiftc -swift-version 6 -module-name PhoenixValleyCore -emit-module -emit-library \
        -module-cache-path "$scratch/swift-cache" Sources/PhoenixValleyCore/*.swift \
        -o "$scratch/libPhoenixValleyCore.dylib" \
        -emit-module-path "$scratch/PhoenixValleyCore.swiftmodule"
    core_args=(-I "$scratch" -L "$scratch" -lPhoenixValleyCore -Xlinker -rpath -Xlinker "$scratch")
fi
swiftc -swift-version 6 "${core_args[@]}" -module-cache-path "$scratch/swift-cache" \
    PhoenixValleyApp/Persistence/ProjectFileStore.swift \
    PhoenixValleyApp/Features/RoadDocumentStore.swift \
    Tests/PhoenixValleyImportStoreSmoke/main.swift -o "$scratch/import-store"
"$scratch/import-store" "$scratch/library"
