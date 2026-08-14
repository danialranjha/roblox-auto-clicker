#!/bin/zsh

set -e
project_dir="${0:A:h}"
source_file="$project_dir/Sources/RobloxReplay/main.swift"
build_dir="$project_dir/.build/standalone"
binary="$build_dir/roblox-replay"
module_cache="$build_dir/module-cache"

mkdir -p "$build_dir"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" || "$0" -nt "$binary" ]]; then
    # Use the compiler and current SDK from the same selected Apple toolchain.
    # Mixing a newer compiler with a hard-coded older SDK can load two
    # incompatible SwiftBridging module maps.
    swift_compiler="$(xcrun --sdk macosx --find swiftc)"
    sdk="$(xcrun --sdk macosx --show-sdk-path)"
    unversioned_target="$("$swift_compiler" -print-target-info | sed -n 's/.*"unversionedTriple": "\([^"]*\)".*/\1/p')"
    if [[ "$unversioned_target" != *-apple-macosx ]]; then
        echo "Unable to determine the macOS target from $swift_compiler" >&2
        exit 1
    fi
    target="${unversioned_target}13.0"

    # Do not reuse Clang modules produced by a previous SDK/toolchain pairing.
    rm -rf "$module_cache"
    mkdir -p "$module_cache"

    echo "Building Roblox Replay…"
    env -u SDKROOT -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
        CLANG_MODULE_CACHE_PATH="$module_cache" \
        "$swift_compiler" \
        -sdk "$sdk" \
        -target "$target" \
        "$source_file" \
        -o "$binary" \
        -framework AppKit \
        -framework ApplicationServices
fi

set +e
"$binary" "$@"
exit_status=$?
set -e

echo
read "?Press Return to close…" || true
exit "$exit_status"
