#!/usr/bin/env bash
# Shared settings and helpers for Tidebar's developer scripts. Source this file; don't run it.

set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly XCODE_SCHEME="Tidebar"
readonly UNIT_TEST_TARGET="TidebarTests"
readonly MINIMUM_XCODE_MAJOR_VERSION=27
readonly MINIMUM_MACOS_MAJOR_VERSION=14
readonly DERIVED_DATA_PATH="${REPOSITORY_ROOT}/build/DerivedData"
readonly SWIFT_SOURCE_DIRECTORIES=("${REPOSITORY_ROOT}/Tidebar" "${REPOSITORY_ROOT}/TidebarTests")

# Ad-hoc signing ("Sign to Run Locally"), so builds work without the maintainer's Apple developer team.
readonly AD_HOC_SIGNING_SETTINGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)

print_step() {
    printf '\n\033[1;34m==> %s\033[0m\n' "$1"
}

print_success() {
    printf '\033[1;32m✓ %s\033[0m\n' "$1"
}

print_warning() {
    printf '\033[1;33m! %s\033[0m\n' "$1" >&2
}

fail_with_message() {
    printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2
    exit 1
}

installed_xcode_major_version() {
    xcodebuild -version 2>/dev/null | awk 'NR == 1 { split($2, versionParts, "."); print versionParts[1] }'
}

require_supported_xcode() {
    local selectedDeveloperDirectory
    selectedDeveloperDirectory="$(xcode-select -p 2>/dev/null || true)"
    if [[ -z "${selectedDeveloperDirectory}" || "${selectedDeveloperDirectory}" == *CommandLineTools* ]]; then
        fail_with_message "Xcode is not selected (found: '${selectedDeveloperDirectory:-nothing}'). Install Xcode ${MINIMUM_XCODE_MAJOR_VERSION}+ and run: sudo xcode-select -s /Applications/Xcode.app"
    fi

    local xcodeMajorVersion
    xcodeMajorVersion="$(installed_xcode_major_version)"
    if [[ -z "${xcodeMajorVersion}" || "${xcodeMajorVersion}" -lt "${MINIMUM_XCODE_MAJOR_VERSION}" ]]; then
        fail_with_message "Xcode ${MINIMUM_XCODE_MAJOR_VERSION}+ is required (found: $(xcodebuild -version 2>/dev/null | head -1 || echo none))."
    fi
}

require_swift_format() {
    if ! xcrun --find swift-format >/dev/null 2>&1; then
        fail_with_message "swift-format was not found in the selected Xcode toolchain. Xcode ${MINIMUM_XCODE_MAJOR_VERSION}+ includes it."
    fi
}
