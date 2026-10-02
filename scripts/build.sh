#!/usr/bin/env bash
# Builds the app with ad-hoc signing.
#
# Usage:
#   scripts/build.sh            Debug build.
#   scripts/build.sh Release    Release build (also checks that nothing depends on debug-only code).

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

buildConfiguration="${1:-Debug}"
case "${buildConfiguration}" in
    Debug | Release) ;;
    *) fail_with_message "Configuration must be Debug or Release (got: ${buildConfiguration})" ;;
esac

require_supported_xcode
cd "${REPOSITORY_ROOT}"

print_step "Building ${XCODE_SCHEME} (${buildConfiguration})"
xcodebuild build \
    -quiet \
    -scheme "${XCODE_SCHEME}" \
    -configuration "${buildConfiguration}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    "${AD_HOC_SIGNING_SETTINGS[@]}"
print_success "Built ${DERIVED_DATA_PATH}/Build/Products/${buildConfiguration}/${XCODE_SCHEME}.app"
