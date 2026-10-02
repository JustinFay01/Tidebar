#!/usr/bin/env bash
# Lints all Swift sources with swift-format using the repository's .swift-format configuration.
#
# Usage:
#   scripts/lint.sh          Report problems and exit non-zero if any are found (used by CI).
#   scripts/lint.sh --fix    Reformat files in place, then lint what remains.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

shouldFixInPlace=false
for argument in "$@"; do
    case "${argument}" in
        --fix) shouldFixInPlace=true ;;
        *) fail_with_message "Unknown option: ${argument}" ;;
    esac
done

require_supported_xcode
require_swift_format
cd "${REPOSITORY_ROOT}"

if [[ "${shouldFixInPlace}" == true ]]; then
    print_step "Formatting Swift sources"
    xcrun swift-format format --in-place --recursive --parallel "${SWIFT_SOURCE_DIRECTORIES[@]}"
fi

print_step "Linting Swift sources"
if xcrun swift-format lint --strict --recursive --parallel "${SWIFT_SOURCE_DIRECTORIES[@]}"; then
    print_success "Lint passed"
else
    fail_with_message "Lint failed. Run 'scripts/lint.sh --fix' to fix formatting; fix the remaining issues by hand."
fi
