#!/usr/bin/env bash
# Builds the app and runs the unit tests with ad-hoc signing.
#
# Usage:
#   scripts/test.sh                                Run all unit tests.
#   scripts/test.sh --result-bundle <path>         Also save an .xcresult bundle (used by CI).

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

resultBundlePath=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --result-bundle)
            [[ $# -ge 2 ]] || fail_with_message "--result-bundle needs a path"
            resultBundlePath="$2"
            shift 2
            ;;
        *) fail_with_message "Unknown option: $1" ;;
    esac
done

require_supported_xcode
cd "${REPOSITORY_ROOT}"

resultBundleArguments=()
if [[ -n "${resultBundlePath}" ]]; then
    rm -rf "${resultBundlePath}"
    resultBundleArguments=(-resultBundlePath "${resultBundlePath}")
fi

print_step "Running unit tests"
xcodebuild test \
    -quiet \
    -scheme "${XCODE_SCHEME}" \
    -destination 'platform=macOS' \
    -only-testing:"${UNIT_TEST_TARGET}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    "${resultBundleArguments[@]+"${resultBundleArguments[@]}"}" \
    "${AD_HOC_SIGNING_SETTINGS[@]}"
print_success "Unit tests passed"
