#!/usr/bin/env bash
# Writes the Tidebar cask for a release and pushes it to the Homebrew tap (JustinFay01/homebrew-tap).
# Called by release/release.sh --publish; can also be run by hand to fix up a cask.
#
# Usage:
#   release/update-homebrew-cask.sh <version> <sha256>              Update the cask and push it.
#   release/update-homebrew-cask.sh <version> <sha256> --no-push    Write and commit the cask without pushing.
#
# Set TIDEBAR_TAP_DIRECTORY to use an existing checkout of the tap instead of a fresh clone.

source "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"

readonly TAP_REPOSITORY="JustinFay01/homebrew-tap"
readonly CASK_RELATIVE_PATH="Casks/tidebar.rb"

[[ $# -ge 2 ]] || fail_with_message "Usage: release/update-homebrew-cask.sh <version> <sha256> [--no-push]"
readonly CASK_VERSION="$1"
readonly CASK_SHA256="$2"
shouldPush=true
[[ "${3:-}" == "--no-push" ]] && shouldPush=false

[[ "${CASK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail_with_message "Version must look like 1.2.3 (got: ${CASK_VERSION})"
[[ "${CASK_SHA256}" =~ ^[0-9a-f]{64}$ ]] || fail_with_message "SHA-256 must be 64 lowercase hex characters."

tapDirectory="${TIDEBAR_TAP_DIRECTORY:-${REPOSITORY_ROOT}/build/homebrew-tap}"

prepare_tap_checkout() {
    print_step "Preparing ${TAP_REPOSITORY} in ${tapDirectory}"
    if [[ -d "${tapDirectory}/.git" ]]; then
        git -C "${tapDirectory}" pull --quiet --ff-only
    else
        rm -rf "${tapDirectory}"
        gh repo clone "${TAP_REPOSITORY}" "${tapDirectory}" -- --quiet
    fi
    print_success "Tap checkout ready"
}

write_cask() {
    print_step "Writing ${CASK_RELATIVE_PATH} for ${CASK_VERSION}"
    mkdir -p "$(dirname "${tapDirectory}/${CASK_RELATIVE_PATH}")"
    cat >"${tapDirectory}/${CASK_RELATIVE_PATH}" <<CASK
cask "tidebar" do
  version "${CASK_VERSION}"
  sha256 "${CASK_SHA256}"

  url "https://github.com/JustinFay01/Tidebar/releases/download/v#{version}/Tidebar-#{version}.zip"
  name "Tidebar"
  desc "Menu bar app showing live Dexcom glucose readings"
  homepage "https://github.com/JustinFay01/Tidebar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Tidebar.app"

  uninstall quit: "com.jnfcorp.Tidebar"

  zap trash: [
    "~/Library/Application Scripts/com.jnfcorp.Tidebar",
    "~/Library/Containers/com.jnfcorp.Tidebar",
  ]
end
CASK
    print_success "Cask written"
}

commit_and_push_cask() {
    print_step "Committing the cask"
    git -C "${tapDirectory}" add "${CASK_RELATIVE_PATH}"
    if git -C "${tapDirectory}" diff --cached --quiet; then
        print_success "Cask already up to date"
        return
    fi
    git -C "${tapDirectory}" commit --quiet -m "tidebar ${CASK_VERSION}"
    if [[ "${shouldPush}" == true ]]; then
        git -C "${tapDirectory}" push --quiet
        print_success "Pushed tidebar ${CASK_VERSION} to ${TAP_REPOSITORY}"
    else
        print_success "Committed tidebar ${CASK_VERSION} (not pushed)"
    fi
}

prepare_tap_checkout
write_cask
commit_and_push_cask
printf '\nInstall with: brew install --cask justinfay01/tap/tidebar\n'
