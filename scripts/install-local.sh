#!/usr/bin/env bash
# Builds a Release copy of Tidebar and installs it on this Mac, for day-to-day use and testing.
#
# Usage:
#   scripts/install-local.sh                     Sign with your Apple Development certificate (recommended).
#   scripts/install-local.sh --ad-hoc            Sign ad hoc, if you don't have an Apple developer team.
#   scripts/install-local.sh --destination DIR   Install into DIR instead of /Applications.
#
# The Dexcom password is stored in the data protection keychain, which needs a build signed with
# your certificate. An ad-hoc copy runs but can't save or read the password.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

readonly APPLICATION_BUNDLE_IDENTIFIER="com.jnfcorp.Tidebar"
readonly SECONDS_TO_WAIT_FOR_QUIT=10

shouldSignAdHoc=false
installationDirectory="/Applications"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ad-hoc)
            shouldSignAdHoc=true
            shift
            ;;
        --destination)
            [[ $# -ge 2 ]] || fail_with_message "--destination needs a directory"
            installationDirectory="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) fail_with_message "Unknown option: $1 (see --help)" ;;
    esac
done

readonly BUILT_APPLICATION_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${XCODE_SCHEME}.app"
readonly INSTALLED_APPLICATION_PATH="${installationDirectory}/${XCODE_SCHEME}.app"

build_release_application() {
    print_step "Building ${XCODE_SCHEME} (Release)"
    # The keychain access group needs a provisioning profile; let Xcode create or refresh it.
    local signingArguments=(-allowProvisioningUpdates)
    if [[ "${shouldSignAdHoc}" == true ]]; then
        signingArguments=("${AD_HOC_SIGNING_SETTINGS[@]}")
    fi
    if ! xcodebuild build \
        -quiet \
        -scheme "${XCODE_SCHEME}" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        "${signingArguments[@]+"${signingArguments[@]}"}"; then
        fail_with_message "Build failed. If the error is about signing or your team, rerun with --ad-hoc."
    fi
    print_success "Built ${BUILT_APPLICATION_PATH}"
}

describe_signature() {
    codesign --display --verbose=2 "$1" 2>&1 | awk -F= '/^Authority=/ { print $2; exit } /^Signature=adhoc/ { print "ad hoc"; exit }'
}

verify_signature() {
    print_step "Verifying signature"
    codesign --verify --deep --strict "${BUILT_APPLICATION_PATH}" ||
        fail_with_message "The built app's signature is invalid."
    print_success "Signed by: $(describe_signature "${BUILT_APPLICATION_PATH}")"
}

is_tidebar_running() {
    pgrep -x "${XCODE_SCHEME}" >/dev/null 2>&1
}

# Quits every running copy, including one launched from Xcode, so only the installed copy remains.
quit_running_copies() {
    if ! is_tidebar_running; then
        return
    fi
    print_step "Quitting running copies of ${XCODE_SCHEME}"
    local secondsWaited=0
    while is_tidebar_running && [[ "${secondsWaited}" -lt "${SECONDS_TO_WAIT_FOR_QUIT}" ]]; do
        osascript -e "tell application id \"${APPLICATION_BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
        sleep 1
        secondsWaited=$((secondsWaited + 1))
    done
    if is_tidebar_running; then
        print_warning "A copy didn't quit in time; stopping it."
        pkill -x "${XCODE_SCHEME}" || true
        sleep 1
    fi
    print_success "No copies running"
}

install_application() {
    print_step "Installing to ${INSTALLED_APPLICATION_PATH}"
    [[ -d "${installationDirectory}" ]] || fail_with_message "${installationDirectory} does not exist."
    if [[ -e "${INSTALLED_APPLICATION_PATH}" ]]; then
        rm -rf "${INSTALLED_APPLICATION_PATH}"
    fi
    ditto "${BUILT_APPLICATION_PATH}" "${INSTALLED_APPLICATION_PATH}"
    print_success "Installed $(defaults read "${INSTALLED_APPLICATION_PATH}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")"
}

launch_installed_application() {
    print_step "Launching ${INSTALLED_APPLICATION_PATH}"
    open "${INSTALLED_APPLICATION_PATH}"
    print_success "Launched"
}

print_next_steps() {
    cat <<NEXT_STEPS

Tidebar is installed at ${INSTALLED_APPLICATION_PATH}.

  - To start it at login, open Settings… from the installed copy and turn on "Launch at login".
    Launch at login uses the copy you turn it on from, so do it from this one, not from Xcode.
  - Your account and settings are shared with Debug builds (same bundle ID). Running a Debug
    build from Xcode at the same time will show two menu bar items.
  - Rerun this script to update the installed copy.

NEXT_STEPS
}

require_supported_xcode
cd "${REPOSITORY_ROOT}"
build_release_application
verify_signature
quit_running_copies
install_application
launch_installed_application
print_next_steps
