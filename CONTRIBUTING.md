# Contributing

Contributions are welcome through [GitHub issues](https://github.com/lurenyang418/zvec-swift/issues) and pull requests.

## Setup

1. Install Xcode 16.4+, CMake 3.26+, Ninja, and Git.
2. Run `scripts/build-xcframework.sh macos` for a development artifact or `scripts/build-xcframework.sh all` for release slices.
3. Run `scripts/verify-xcframework.sh`, `swift test`, and `swift build -c release`.
4. Run `scripts/generate-docs.sh` to verify DocC output in `.build/docc`.

The native source is fetched at the exact commit recorded in `scripts/native-version.env`. Do not update the tag without also updating the commit, compatibility check, changelog, binary release, and integration tests.

## Pull requests

- Keep public APIs `Sendable` under Swift 6 strict concurrency.
- Every C allocation must have an explicit owner and matching release path.
- Add tests for success, native failure, closed-handle behavior, and async behavior.
- Run `git diff --check` before submitting.
- Run `xcrun swift-format lint --recursive --strict --configuration .swift-format Sources Tests Package.swift`.
- Update `CHANGELOG.md` for user-visible changes.

For security reports, follow [SECURITY.md](SECURITY.md) rather than opening a public issue.
