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
- Filter-only Browse API with explicit bounded-result semantics.
- Natural-language and advanced-expression full-text query modes.
- Dense vector queries sourced from an existing document ID.
- Structured native version, Collection location/closed-state introspection,
  DataType classifications, single-document CRUD, ordered Fetch results, and
  schema-aware local document validation.
- Python v0.5.1 capability parity matrix documenting C API, Apple-platform,
  and Python-only embedding boundaries.

### Changed

- Reject indexed sparse-vector fields on Apple before upstream Zvec v0.5.1 can
  abort; sparse brute-force queries remain supported.
- Batch Fetch now includes vector fields by default, matching the Python API;
  pass `includeVector: false` to retain the previous behavior.
- `FullTextQuery` now stores `FullTextExpression`; the existing `query:`
  initializer remains available and maps to natural-language `.match`.

### Fixed

- Preserve IVF and Flat radius/linear-search parameters on multi-query subqueries.
- Reject native 32-bit integer overflows and zero runtime thread counts instead
  of allowing traps or deferring validation to CZvec.
- Handle C-string allocation failures without passing null pointers to CZvec.
- Prevent double destruction when a native query wrapper initializer fails.
