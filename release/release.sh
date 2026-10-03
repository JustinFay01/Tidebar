#!/usr/bin/env bash
# Builds a signed, notarized release of Tidebar and, optionally, publishes it.
#
# Usage:
#   release/release.sh <version>                Build, sign, notarize, and zip (nothing is published).
#   release/release.sh <version> --publish      Also tag v<version>, create the GitHub release, and update the Homebrew cask.
#
# Options:
#   --notary-profile <name>   notarytool keychain profile (default: tidebar-notary).
#   --skip-notarization       Sign only; for checking the build locally. Can't be combined with --publish.
#
# See release/README.md for the full runbook. One-time setup:
#   1. Developer ID signing: automatic for the Account Holder (cloud-managed certificate), or a local
#      certificate from Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials tidebar-notary --apple-id <email> --team-id <your team ID>
#   Releases are signed with the project's team (Tidebar target → Signing & Capabilities), which must
#   be a paid Apple Developer Program team; free Personal Teams can't create Developer ID certificates.
#
# Output goes to build/release/: Tidebar-<version>.zip and Tidebar-<version>.zip.sha256.

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"

readonly RELEASE_DIRECTORY="${REPOSITORY_ROOT}/build/release"
readonly ARCHIVE_PATH="${RELEASE_DIRECTORY}/${XCODE_SCHEME}.xcarchive"
readonly EXPORT_DIRECTORY="${RELEASE_DIRECTORY}/export"
readonly EXPORTED_APPLICATION_PATH="${EXPORT_DIRECTORY}/${XCODE_SCHEME}.app"
readonly GITHUB_REPOSITORY="JustinFay01/Tidebar"

releaseVersion=""
shouldPublish=false
shouldSkipNotarization=false
notaryKeychainProfile="tidebar-notary"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish)
            shouldPublish=true
            shift
            ;;
        --skip-notarization)
            shouldSkipNotarization=true
            shift
            ;;
        --notary-profile)
            [[ $# -ge 2 ]] || fail_with_message "--notary-profile needs a name"
            notaryKeychainProfile="$2"
            shift 2
            ;;
        -h | --help)
            sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) fail_with_message "Unknown option: $1 (see --help)" ;;
        *)
            [[ -z "${releaseVersion}" ]] || fail_with_message "Only one version can be given"
            releaseVersion="$1"
            shift
            ;;
    esac
done

readonly RELEASE_TAG="v${releaseVersion}"
readonly RELEASE_ARCHIVE_NAME="${XCODE_SCHEME}-${releaseVersion}.zip"
readonly RELEASE_ARCHIVE_PATH="${RELEASE_DIRECTORY}/${RELEASE_ARCHIVE_NAME}"

# MARK: - Checks

validate_arguments() {
    [[ -n "${releaseVersion}" ]] || fail_with_message "Give a version, e.g. release/release.sh 1.1.0"
    [[ "${releaseVersion}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail_with_message "Version must look like 1.2.3 (got: ${releaseVersion})"
    if [[ "${shouldPublish}" == true && "${shouldSkipNotarization}" == true ]]; then
        fail_with_message "--publish requires notarization; remove --skip-notarization."
    fi
}

check_repository_state() {
    print_step "Checking repository"
    if [[ -n "$(git status --porcelain)" ]]; then
        [[ "${shouldPublish}" == false ]] || fail_with_message "The working tree has uncommitted changes."
        print_warning "Uncommitted changes; fine for a local build, but publish only from a clean main."
    fi
    if [[ "${shouldPublish}" == true ]]; then
        local currentBranch
        currentBranch="$(git branch --show-current)"
        [[ "${currentBranch}" == "main" ]] || fail_with_message "Publish from main (currently on ${currentBranch})."
        git fetch --quiet origin main --tags
        [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] ||
            fail_with_message "Local main differs from origin/main. Pull or push first."
        if git rev-parse --quiet --verify "refs/tags/${RELEASE_TAG}" >/dev/null; then
            fail_with_message "Tag ${RELEASE_TAG} already exists. Choose a new version."
        fi
        command -v gh >/dev/null || fail_with_message "The GitHub CLI (gh) is needed to publish."
    fi
    print_success "Releasing ${releaseVersion} from $(git rev-parse --short HEAD)"
}

check_signing_identity() {
    print_step "Checking signing identity"
    [[ -n "${DEVELOPER_TEAM_IDENTIFIER}" ]] || fail_with_message "The project has no DEVELOPMENT_TEAM set."
    print_success "Signing team: ${DEVELOPER_TEAM_IDENTIFIER}"
    if ! security find-identity -v -p codesigning | grep -q "Developer ID Application:.*(${DEVELOPER_TEAM_IDENTIFIER})"; then
        print_warning "No local Developer ID Application certificate; export will use Xcode's cloud-managed one."
        print_warning "That needs the team's Account Holder signed in to Xcode. See release/README.md if export fails."
    else
        print_success "Developer ID Application certificate found"
    fi
}

check_notary_profile() {
    [[ "${shouldSkipNotarization}" == true ]] && return
    print_step "Checking notarization credentials"
    xcrun notarytool history --keychain-profile "${notaryKeychainProfile}" >/dev/null 2>&1 ||
        fail_with_message "Notary profile '${notaryKeychainProfile}' doesn't work. Create it with: xcrun notarytool store-credentials ${notaryKeychainProfile} --apple-id <email> --team-id ${DEVELOPER_TEAM_IDENTIFIER}"
    print_success "Notary profile '${notaryKeychainProfile}' works"
}

# MARK: - Build

# Commits on main only ever increase, so this gives every release a higher build number.
current_build_number() {
    git rev-list --count HEAD
}

archive_application() {
    print_step "Archiving ${XCODE_SCHEME} ${releaseVersion} (build $(current_build_number))"
    rm -rf "${RELEASE_DIRECTORY}"
    mkdir -p "${RELEASE_DIRECTORY}"
    xcodebuild archive \
        -quiet \
        -scheme "${XCODE_SCHEME}" \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -archivePath "${ARCHIVE_PATH}" \
        -allowProvisioningUpdates \
        MARKETING_VERSION="${releaseVersion}" \
        CURRENT_PROJECT_VERSION="$(current_build_number)"
    print_success "Archived ${ARCHIVE_PATH}"
}

export_with_developer_id() {
    print_step "Exporting with Developer ID signing"
    local exportOptionsPath="${RELEASE_DIRECTORY}/ExportOptions.plist"
    cat >"${exportOptionsPath}" <<EXPORT_OPTIONS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>${DEVELOPER_TEAM_IDENTIFIER}</string>
</dict>
</plist>
EXPORT_OPTIONS
    xcodebuild -exportArchive \
        -quiet \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_DIRECTORY}" \
        -exportOptionsPlist "${exportOptionsPath}" \
        -allowProvisioningUpdates
    [[ -d "${EXPORTED_APPLICATION_PATH}" ]] || fail_with_message "Export didn't produce ${EXPORTED_APPLICATION_PATH}"
    print_success "Exported ${EXPORTED_APPLICATION_PATH}"
}

# Notarization rejects apps that aren't Developer ID signed with the hardened runtime, or that
# still carry the debugging entitlement.
verify_signature() {
    print_step "Verifying signature"
    codesign --verify --deep --strict "${EXPORTED_APPLICATION_PATH}" || fail_with_message "Signature is invalid."
    local signatureDetails
    signatureDetails="$(codesign --display --verbose=4 "${EXPORTED_APPLICATION_PATH}" 2>&1)"
    grep -q "^Authority=Developer ID Application:.*(${DEVELOPER_TEAM_IDENTIFIER})" <<<"${signatureDetails}" ||
        fail_with_message "Not signed with a Developer ID Application certificate for ${DEVELOPER_TEAM_IDENTIFIER}."
    grep -q "flags=.*runtime" <<<"${signatureDetails}" || fail_with_message "Hardened runtime is not enabled."
    if codesign --display --entitlements - --xml "${EXPORTED_APPLICATION_PATH}" 2>/dev/null | grep -q "get-task-allow"; then
        fail_with_message "The app has the get-task-allow (debugging) entitlement."
    fi
    print_success "$(grep -m1 '^Authority=' <<<"${signatureDetails}" | cut -d= -f2), hardened runtime"
    print_success "Architectures: $(lipo -archs "${EXPORTED_APPLICATION_PATH}/Contents/MacOS/${XCODE_SCHEME}")"
}

# MARK: - Notarization

notarize_and_staple() {
    if [[ "${shouldSkipNotarization}" == true ]]; then
        print_warning "Skipping notarization; this build will be blocked by Gatekeeper on other Macs."
        return
    fi
    print_step "Submitting to Apple for notarization (usually a few minutes)"
    local submissionArchivePath="${RELEASE_DIRECTORY}/notarization-submission.zip"
    ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APPLICATION_PATH}" "${submissionArchivePath}"

    local submissionResult
    submissionResult="$(xcrun notarytool submit "${submissionArchivePath}" \
        --keychain-profile "${notaryKeychainProfile}" --wait --output-format json)" ||
        true
    local submissionStatus submissionIdentifier
    submissionStatus="$(plutil -extract status raw - <<<"${submissionResult}" 2>/dev/null || echo "unknown")"
    submissionIdentifier="$(plutil -extract id raw - <<<"${submissionResult}" 2>/dev/null || echo "")"
    if [[ "${submissionStatus}" != "Accepted" ]]; then
        print_warning "Notarization status: ${submissionStatus}"
        if [[ -n "${submissionIdentifier}" ]]; then
            xcrun notarytool log "${submissionIdentifier}" --keychain-profile "${notaryKeychainProfile}" >&2 || true
        fi
        fail_with_message "Notarization failed. See Apple's log above."
    fi
    rm -f "${submissionArchivePath}"
    print_success "Notarized (submission ${submissionIdentifier})"

    print_step "Stapling the notarization ticket"
    xcrun stapler staple "${EXPORTED_APPLICATION_PATH}" >/dev/null
    xcrun stapler validate "${EXPORTED_APPLICATION_PATH}" >/dev/null || fail_with_message "Stapled ticket didn't validate."
    print_success "Ticket stapled"

    print_step "Checking Gatekeeper"
    local gatekeeperAssessment
    gatekeeperAssessment="$(spctl --assess --type execute --verbose=2 "${EXPORTED_APPLICATION_PATH}" 2>&1)" ||
        fail_with_message "Gatekeeper rejected the app: ${gatekeeperAssessment}"
    grep -q "source=Notarized Developer ID" <<<"${gatekeeperAssessment}" ||
        fail_with_message "Gatekeeper didn't see a notarized Developer ID app: ${gatekeeperAssessment}"
    print_success "Gatekeeper: accepted, notarized Developer ID"
}

package_release_archive() {
    print_step "Packaging ${RELEASE_ARCHIVE_NAME}"
    ditto -c -k --sequesterRsrc --keepParent "${EXPORTED_APPLICATION_PATH}" "${RELEASE_ARCHIVE_PATH}"
    (cd "${RELEASE_DIRECTORY}" && shasum -a 256 "${RELEASE_ARCHIVE_NAME}" >"${RELEASE_ARCHIVE_NAME}.sha256")
    print_success "${RELEASE_ARCHIVE_PATH}"
    print_success "SHA-256 $(release_archive_checksum)"
}

release_archive_checksum() {
    awk '{ print $1 }' "${RELEASE_ARCHIVE_PATH}.sha256"
}

# MARK: - Publishing

publish_release() {
    print_step "Tagging ${RELEASE_TAG}"
    git tag -a "${RELEASE_TAG}" -m "Tidebar ${releaseVersion}"
    git push --quiet origin "${RELEASE_TAG}"
    print_success "Pushed ${RELEASE_TAG}"

    print_step "Creating the GitHub release"
    gh release create "${RELEASE_TAG}" \
        "${RELEASE_ARCHIVE_PATH}" "${RELEASE_ARCHIVE_PATH}.sha256" \
        --repo "${GITHUB_REPOSITORY}" \
        --title "Tidebar ${releaseVersion}" \
        --generate-notes \
        --verify-tag
    print_success "https://github.com/${GITHUB_REPOSITORY}/releases/tag/${RELEASE_TAG}"

    "${REPOSITORY_ROOT}/release/update-homebrew-cask.sh" "${releaseVersion}" "$(release_archive_checksum)"
}

validate_arguments
require_supported_xcode
cd "${REPOSITORY_ROOT}"
DEVELOPER_TEAM_IDENTIFIER="$(project_development_team)"
readonly DEVELOPER_TEAM_IDENTIFIER
check_repository_state
check_signing_identity
check_notary_profile
archive_application
export_with_developer_id
verify_signature
notarize_and_staple
package_release_archive
if [[ "${shouldPublish}" == true ]]; then
    publish_release
else
    printf '\nNot published. To publish, run: release/release.sh %s --publish\n' "${releaseVersion}"
fi
