# Contributing

Contributions are welcome through [GitHub issues](https://github.com/lurenyang418/zvec-swift/issues) and pull requests.

## Setup

1. Install Xcode 16.4+, CMake 3.26+, Ninja, and Git.
2. Run `scripts/build-xcframework.sh macos` for a development artifact or `scripts/build-xcframework.sh all` for release slices.
3. Run `scripts/verify-xcframework.sh`, `swift test`, and `swift build -c release`.
4. Run `scripts/generate-docs.sh` to verify DocC output in `.build/docc`.

The native source is fetched at the exact commit recorded in `scripts/native-version.env`. Do not update the tag without also updating the commit, compatibility check, changelog, binary release, and integration tests.

## Native and package releases

The manually approved **Native release** workflow owns binary production and package publication, following the distribution-repository pattern used by established Swift binary packages:

1. Update `ZVEC_VERSION` and `ZVEC_COMMIT` in `scripts/native-version.env`, plus the matching `nativeVersion` in `Package.swift`, and merge those reviewed source changes to `main`.
2. Run **Native release** from `main`. The macOS runner builds all Apple slices, verifies and packages the XCFramework, computes the checksum, and changes only the checksum in `Package.swift`.
3. The workflow tests that release candidate, commits the checksum to `main`, attaches build provenance, publishes `native-vX.Y.Z`, and finally creates the Swift package tag `vX.Y.Z` at the checksum commit.

The workflow has `contents: write` because it pushes the checksum commit and tags. A protected `main` branch must explicitly allow this release workflow to push; otherwise it fails before publishing the release.

For local diagnostics, `scripts/package-native.sh` uses the same metadata-free ZIP command, and `scripts/verify-native-archive.sh` verifies the archive after extraction. Do not upload a locally generated ZIP as the official release asset.

## Pull requests

- Keep public APIs `Sendable` under Swift 6 strict concurrency.
- Every C allocation must have an explicit owner and matching release path.
- Add tests for success, native failure, closed-handle behavior, and async behavior.
- Run `git diff --check` before submitting.
- Run `xcrun swift-format lint --recursive --strict --configuration .swift-format Sources Tests Package.swift`.
- Update `CHANGELOG.md` for user-visible changes.

For security reports, follow [SECURITY.md](SECURITY.md) rather than opening a public issue.
