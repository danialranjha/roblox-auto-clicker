#!/bin/zsh

set -e
project_dir="${0:A:h}"
source_file="$project_dir/Sources/RobloxReplay/main.swift"
build_dir="$project_dir/.build/standalone"
binary="$build_dir/roblox-replay"
module_cache="$build_dir/module-cache"

mkdir -p "$module_cache"

if [[ ! -x "$binary" || "$source_file" -nt "$binary" ]]; then
    swift_compiler="$(xcrun --find swiftc)"
    target="$(uname -m)-apple-macosx13.0"
    sdk_arguments=()

    # Some Command Line Tools releases ship a default SDK whose Swift module is
    # older than their compiler. The 14.5 SDK is a compatible fallback when it
    # is installed; otherwise xcrun's current default is used.
    compatible_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk"
    if [[ -d "$compatible_sdk" ]]; then
        sdk_arguments=(-sdk "$compatible_sdk")
    fi

    echo "Building Roblox Replay…"
    env CLANG_MODULE_CACHE_PATH="$module_cache" \
        "$swift_compiler" \
        "${sdk_arguments[@]}" \
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
