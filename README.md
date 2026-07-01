# Zvec Swift

[简体中文](README_CN.md) | English

Safe, idiomatic Swift 6.1 bindings for [Alibaba Zvec](https://github.com/alibaba/zvec), an in-process vector database.

> Status: active development against Zvec v0.5.1. The public API is not stable until the first tagged release.

## Features

- Native Swift value types and typed errors over the complete Zvec C API.
- Dense and sparse vectors, scalar fields, arrays, full-text search, and hybrid queries.
- Filter-only browsing, advanced full-text expressions, and vector query by document ID.
- HNSW, IVF, Flat, inverted, and FTS indexes on Apple platforms.
- Synchronous and Swift Concurrency APIs with thread-safe collection lifetime management.
- SwiftPM distribution through a prebuilt `CZvec.xcframework`; no CMake toolchain required by consumers.

## Requirements

- Swift 6.1 / Xcode 16.4 or newer
- macOS 13+ on Apple Silicon
- iOS 16+ on arm64 devices or Apple Silicon simulators

DiskANN/Vamana is present in the API for source compatibility but is unavailable on Apple platforms because upstream enables it only on Linux x86_64.
Zvec v0.5.1 also aborts while creating indexed sparse-vector fields on Apple;
the Swift layer rejects that unsafe configuration and keeps sparse queries
available through upstream's brute-force path.

## Installation

Add the package in Xcode or in `Package.swift`:

```swift
.package(url: "https://github.com/lurenyang418/zvec-swift.git", from: "0.5.1")
```

Then add `Zvec` to the target dependencies.

## Quick start

```swift
import Zvec

try ZvecRuntime.initialize()
defer { try? ZvecRuntime.shutdown() }

let schema = try CollectionSchema("demo") {
    try VectorField("embedding", type: .float32, dimensions: 4,
                    index: .hnsw(metric: .cosine))
    try Field("title", type: .string, index: .fullText())
    try Field("category", type: .string)
}

let collection = try Collection.create(
    at: URL(filePath: "./zvec-demo"),
    schema: schema
)
defer { try? collection.close() }

try collection.insert(Document(id: "doc-1", fields: [
    "title": .string("hello"),
    "category": .string("example"),
    "embedding": .vectorFloat32([0.1, 0.2, 0.3, 0.4]),
]))

let hits = try collection.query(VectorQuery(
    field: "embedding",
    vector: .float32([0.4, 0.3, 0.3, 0.1]),
    topK: 10
))

let rows = try collection.browse(BrowseQuery(limit: 50))
let related = try collection.query(VectorQuery(
    field: "embedding",
    documentID: "doc-1",
    topK: 10
))
```

## Query modes

Natural-language FTS and advanced FTS expressions are distinct:

```swift
let textHits = try collection.query(FullTextQuery(
    field: "title",
    expression: .query("+swift -server"),
    topK: 10
))
```

Hybrid search uses native RRF or weighted reranking:

```swift
let hybrid = try collection.query(MultiQuery(
    queries: [
        SubQuery(field: "embedding", payload: .dense(.float32([0.1, 0.2, 0.3, 0.4])), topK: 20),
        SubQuery(field: "title", payload: .fullText("swift database"), topK: 20),
    ],
    topK: 10,
    reranker: .reciprocalRankFusion()
))

let groups = try collection.query(GroupByVectorQuery(
    vectorQuery: VectorQuery(field: "embedding", documentID: "doc-1", topK: 10),
    groupByField: "category",
    groupCount: 5,
    groupTopK: 2
))
```

Open an existing collection with `Collection.open(at:)`. Every database operation has an async overload with the same result semantics.

See [`Sources/ZvecExample`](Sources/ZvecExample) for a runnable example and [`plan.md`](plan.md) for the implementation contract.
API documentation source lives in [`Sources/Zvec/Zvec.docc`](Sources/Zvec/Zvec.docc).
The [Python parity matrix](Docs/PythonParity.md) records native and Apple-platform boundaries. Python-only embedding providers and model runtimes are intentionally outside the core package.

## Development

The high-level package expects a local `Artifacts/CZvec.xcframework` while developing. Build it with:

```bash
scripts/build-xcframework.sh
swift test
```

The build pins the exact upstream commit and compiles a narrowly scoped
[native compatibility shim](Native/README.md) for C API gaps in Zvec v0.5.1.
Use `scripts/build-xcframework.sh all` to create macOS, iOS device, and iOS
simulator slices.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete workflow and [upstream build documentation](https://zvec.org/en/docs/build/) for Zvec internals.

## License

Apache License 2.0. Zvec and bundled third-party components retain their respective notices; see [LICENSE](LICENSE) and [NOTICE](NOTICE).
