#!/usr/bin/env bash
# Gets a contributor's machine ready to work on Tidebar: checks tools, installs the git
# pre-commit hook, and runs the same lint, build, and test steps as CI.
#
# Usage:
#   scripts/setup.sh                 Full setup and verification.
#   scripts/setup.sh --skip-checks   Check tools and install hooks, but don't lint, build, or test.
#   scripts/setup.sh --no-hooks      Don't install the git pre-commit hook.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

shouldRunChecks=true
shouldInstallHooks=true
for argument in "$@"; do
    case "${argument}" in
        --skip-checks) shouldRunChecks=false ;;
        --no-hooks) shouldInstallHooks=false ;;
        -h | --help)
            sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) fail_with_message "Unknown option: ${argument} (see --help)" ;;
    esac
done

check_macos_version() {
    print_step "Checking macOS"
    local macosMajorVersion
    macosMajorVersion="$(sw_vers -productVersion | cut -d. -f1)"
    if [[ "${macosMajorVersion}" -lt "${MINIMUM_MACOS_MAJOR_VERSION}" ]]; then
        fail_with_message "macOS ${MINIMUM_MACOS_MAJOR_VERSION}+ is required (found $(sw_vers -productVersion))."
    fi
    print_success "macOS $(sw_vers -productVersion)"
}

check_xcode() {
    print_step "Checking Xcode"
    require_supported_xcode
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        fail_with_message "Xcode needs to finish installing components. Run: sudo xcodebuild -runFirstLaunch"
    fi
    print_success "$(xcodebuild -version | head -1) at $(xcode-select -p)"
}

check_swift_format() {
    print_step "Checking swift-format"
    require_swift_format
    print_success "swift-format $(xcrun swift-format --version 2>/dev/null)"
}

install_git_hooks() {
    print_step "Installing git hooks"
    if ! git -C "${REPOSITORY_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        print_warning "Not a git checkout; skipping hooks."
        return
    fi
    git -C "${REPOSITORY_ROOT}" config core.hooksPath .githooks
    chmod +x "${REPOSITORY_ROOT}/.githooks/"*
    print_success "Pre-commit hook installed (lints staged Swift files). Bypass once with: git commit --no-verify"
}

run_project_checks() {
    "${REPOSITORY_ROOT}/scripts/lint.sh"
    "${REPOSITORY_ROOT}/scripts/build.sh" Release
    "${REPOSITORY_ROOT}/scripts/test.sh"
}

print_next_steps() {
    cat <<'NEXT_STEPS'

You're set up. Useful commands:

  scripts/lint.sh          Lint (same as CI)
  scripts/lint.sh --fix    Auto-format, then lint
  scripts/test.sh          Run unit tests (same as CI)
  scripts/build.sh         Debug build; pass "Release" for a release build

Working in Xcode:
  Open Tidebar.xcodeproj and run the "Tidebar" scheme. Debug builds add a Debug submenu
  that simulates errors and readings, so you don't need a Dexcom account for most work.
  If Xcode reports a signing error, open the Tidebar target's Signing & Capabilities and
  choose your own team (or "Sign to Run Locally"). Please don't commit that change.

NEXT_STEPS
}

check_macos_version
check_xcode
check_swift_format
if [[ "${shouldInstallHooks}" == true ]]; then
    install_git_hooks
fi
if [[ "${shouldRunChecks}" == true ]]; then
    run_project_checks
fi
print_next_steps
