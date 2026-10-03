# Releasing Tidebar

Tidebar releases are built and signed on my Mac rather than in CI, so the Developer ID signing key
never leaves the keychain, and this repository holds no secrets. Two scripts do the work:

- [`release.sh`](release.sh) builds a universal app, signs it with Developer ID, has Apple notarize it,
  and checks the result. With `--publish` it also tags the version, creates the GitHub release, and
  updates the Homebrew cask.
- [`update-homebrew-cask.sh`](update-homebrew-cask.sh) writes `Casks/tidebar.rb` in
  [JustinFay01/homebrew-tap](https://github.com/JustinFay01/homebrew-tap). `release.sh` calls it, and it
  can also be run by hand to fix a cask.

Everything the scripts produce lands in `build/release/`, which git ignores.

## Cutting a release

Versions follow [semantic versioning](https://semver.org): a patch like `1.1.1` for fixes, a minor like
`1.2.0` for new features. The version comes from the command line rather than the project file, and the
build number is the commit count on `main`, so neither needs a commit to bump.

A dry run builds, signs, notarizes, and verifies without publishing anything. Notarization usually
takes a few minutes:

```sh
git switch main && git pull
release/release.sh 1.2.0
```

When that passes, publishing runs the same build again from scratch, then tags `v1.2.0`, uploads
`Tidebar-1.2.0.zip` and its checksum to a GitHub release, and pushes the new cask to the tap:

```sh
release/release.sh 1.2.0 --publish
```

Afterwards, the [release page](https://github.com/JustinFay01/Tidebar/releases/latest) has notes
generated from the merged PRs, which are worth editing into something users can read.
`brew upgrade --cask tidebar` should install the new version, which opens without a Gatekeeper
warning and shows its version at the bottom of Settings.

## What the script checks

`release.sh` stops before anything is published if the build isn't right. It only publishes from a
clean `main` that matches GitHub, with a tag that doesn't exist yet. The app has to be signed with a
**Developer ID Application** certificate from the project's team, use the hardened runtime, and not
carry the `get-task-allow` debugging entitlement. Apple has to accept it for notarization (if not, the
script prints Apple's log), the ticket has to staple so the app opens offline, and Gatekeeper has to
accept it as a notarized Developer ID app. It also prints the architectures, which should be both
`arm64` and `x86_64`.

## Troubleshooting

| Problem | What's going on |
|---|---|
| "The selected team does not have a program membership that is eligible for this feature" | The project is set to a free Personal Team. Developer ID needs a paid Apple Developer Program team, selected in the Tidebar target's **Signing & Capabilities**. |
| "No signing certificate 'Developer ID Application' found" | Xcode couldn't use Apple's cloud-managed certificate, which needs the team's Account Holder signed in to Xcode. A local certificate works too: **Xcode → Settings → Accounts → Manage Certificates… → + → Developer ID Application**. |
| "Notary profile 'tidebar-notary' doesn't work" | The stored notarization credentials are missing or out of date; app-specific passwords stop working after an Apple ID password change. Make a new one at [account.apple.com](https://account.apple.com) and run `xcrun notarytool store-credentials tidebar-notary --apple-id <email> --team-id <team ID>`. |
| Notarization status "Invalid" | Apple's log, printed by the script, says why. A missing hardened runtime and unsigned nested code are the usual causes. |
| "Tag vX.Y.Z already exists" | That version is taken. Published tags are never moved or reused, so the release gets the next version. |
| The cask push fails | Usually a GitHub auth problem (`gh auth status`). The cask can be pushed again with `release/update-homebrew-cask.sh <version> <sha256>`, using the values in `build/release/*.sha256`. |

## Homebrew

Tidebar installs from its own tap: `brew install --cask justinfay01/tap/tidebar`. The official
`homebrew/cask` repository only accepts apps that meet its
[notability rules](https://docs.brew.sh/Package-Acceptance-Policy): for a cask submitted by its own
author, at least 225 stars, 90 forks, or 90 watchers (75, 30, or 30 if someone else submits it), and a
repository at least 30 days old. Once Tidebar gets in, Homebrew's automation keeps that cask up to date.

## Why releases aren't built in CI

A GitHub Actions release workflow would need the Developer ID private key stored as a repository
secret, where any workflow that runs on `main` or a tag could read it. Building on my own Mac keeps the
key in a single keychain.
