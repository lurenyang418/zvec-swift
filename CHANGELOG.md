# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Initial Swift 6.1 package structure.
- Two-layer `CZvec` and type-safe `Zvec` bindings for upstream Zvec v0.5.1.
- Synchronous and async collection lifecycle, CRUD, schema evolution, vector,
  full-text, multi-vector, and group-by query APIs.
- Native compatibility shim for exact binary/Boolean array round trips and
  group-by execution on Apple platforms.
- Bundled Jieba dictionaries for Chinese full-text search.
- DocC articles, all-Apple-slice XCFramework verification, and release tooling.
- Native document serialization utilities and complete value-type round-trip coverage.

### Changed

- Reject indexed sparse-vector fields on Apple before upstream Zvec v0.5.1 can
  abort; sparse brute-force queries remain supported.
