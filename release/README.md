# Releasing Tidebar

This is the maintainer runbook for cutting a release. Releases are built and signed on the maintainer's
Mac, so the Developer ID certificate's private key never leaves its keychain. No secrets live in this
repository.

| File | What it does |
|---|---|
| [`release.sh`](release.sh) | Archives, signs with Developer ID, notarizes, staples, and verifies. With `--publish`, also tags, creates the GitHub release, and updates the Homebrew cask. |
| [`update-homebrew-cask.sh`](update-homebrew-cask.sh) | Writes `Casks/tidebar.rb` in [JustinFay01/homebrew-tap](https://github.com/JustinFay01/homebrew-tap) and pushes it. `release.sh --publish` calls it; you can also run it on its own to fix a cask. |

Build output goes to `build/release/`, which git ignores.

## One-time setup

You need four things on the Mac that releases:

1. **A paid Apple Developer Program team set on the project.** Set it in the Tidebar target's
   **Signing & Capabilities**; the scripts read it from there. A free "Personal Team" can't create
   Developer ID certificates.
2. **Developer ID signing.** Nothing to install if you're the team's Account Holder (as on an Individual
   membership): the export step uses `-allowProvisioningUpdates` and signs with an Apple-managed
   ("cloud") Developer ID certificate. Otherwise, create a local certificate: **Xcode → Settings →
   Accounts → Manage Certificates… → + → Developer ID Application**.
3. **Notarization credentials** saved in your keychain as a profile. Create an app-specific password at
   [account.apple.com](https://account.apple.com) (Sign-In and Security → App-Specific Passwords), then:
   ```sh
   xcrun notarytool store-credentials tidebar-notary --apple-id <your Apple ID email> --team-id <team ID>
   ```
4. **The GitHub CLI**, signed in with push access to both this repo and the tap: `gh auth status`.

## Cutting a release

1. **Merge everything for the release into `main`.** CI should pass. Run your installed copy for a day
   or so to make sure nothing's wrong in normal use.
2. **Pick a version** using [semantic versioning](https://semver.org): a patch (`1.1.1`) for fixes, a
   minor (`1.2.0`) for new features. Don't edit the project to bump it; the version comes from the
   command line. The build number is the commit count on `main`, which only ever goes up.
3. **Do a dry run.** This builds, signs, notarizes, and verifies, but publishes nothing:
   ```sh
   git switch main && git pull
   release/release.sh 1.2.0
   ```
   Notarization usually takes a few minutes. Optionally, open `build/release/export/Tidebar.app` to
   check it.
4. **Publish:**
   ```sh
   release/release.sh 1.2.0 --publish
   ```
   This re-runs the build from scratch, then tags `v1.2.0`, creates the GitHub release with
   `Tidebar-1.2.0.zip` and its `.sha256`, and pushes the updated cask to the tap.
5. **Check the release:**
   - The [release page](https://github.com/JustinFay01/Tidebar/releases/latest) has the zip and
     generated notes. Edit the notes to describe what changed for users.
   - `brew update && brew upgrade --cask tidebar` (or `brew install --cask justinfay01/tap/tidebar`)
     installs the new version, and it launches without any Gatekeeper warning.
   - **Copy Diagnostics** in Tidebar's menu shows the new version and build number.

## What the script checks

`release.sh` stops before publishing anything if any of these fail:

- **Publishing from the right place:** you're on `main`, the working tree is clean, local `main`
  matches `origin/main`, and the tag doesn't already exist.
- **Signing:** the app is signed with a **Developer ID Application** certificate from the project's
  team, uses the **hardened runtime**, and does **not** have the `get-task-allow` (debugging)
  entitlement.
- **Notarization:** Apple accepted the build. If not, the script prints Apple's notarization log.
- **Distribution:** the ticket is stapled (so the app opens offline), and Gatekeeper accepts the app
  as a **Notarized Developer ID** app.
- **Architectures:** the script prints them; a release build should include both `arm64` and
  `x86_64`.

## Troubleshooting

| Problem | Fix |
|---|---|
| "The selected team does not have a program membership that is eligible for this feature" | The project is set to a free Personal Team. Select your paid team in **Signing & Capabilities**. |
| "No signing certificate 'Developer ID Application' found" | Xcode couldn't use a cloud-managed certificate: check you're signed in to Xcode with the Account Holder's Apple ID, or create a local certificate (setup step 2). If the + menu only offers Development certificates, the team isn't a paid one, or you aren't its Account Holder. |
| "Notary profile 'tidebar-notary' doesn't work" | Repeat setup step 3. App-specific passwords stop working if you change your Apple ID password. |
| Notarization status "Invalid" | Read the log the script prints. Common causes are a missing hardened runtime and unsigned nested code. |
| "Tag vX.Y.Z already exists" | Choose the next version. Never move or reuse a published tag. |
| Cask push fails | Check `gh auth status` and your access to JustinFay01/homebrew-tap, then rerun `release/update-homebrew-cask.sh <version> <sha256>` with the values from `build/release/*.sha256`. |

## Homebrew

Tidebar is installed from its own tap (`brew install --cask justinfay01/tap/tidebar`). The official
`homebrew/cask` repository requires notability: at least 225 stars, 90 forks, or 90 watchers for a
self-submitted cask (75, 30, or 30 if someone else submits it), and a repository at least 30 days old.
See Homebrew's [acceptance policy](https://docs.brew.sh/Package-Acceptance-Policy). Once Tidebar is
accepted there, Homebrew's automation updates the official cask, and the tap can point users to it.

## Why releases aren't built in CI

A GitHub Actions release workflow would need the Developer ID private key stored as a repository
secret, and any workflow that runs on `main` or a tag could read it. Building on the maintainer's Mac
keeps the key in one keychain. If releases ever need to come from CI, keep the key in a protected
`release` environment that requires approval, and pin every action to a commit SHA.
