# ``Zvec``

Embed Alibaba Zvec in Swift applications with typed schemas, values, errors,
queries, and Swift Concurrency APIs.

## Overview

Initialize ``ZvecRuntime`` once, create or open a ``Collection``, and use
``Document`` values for writes and query results. Public operations use
`throws(ZvecError)` and do not expose native allocation or handle ownership.

```swift
try ZvecRuntime.initialize()

let schema = try CollectionSchema("articles") {
    try Field("title", type: .string, index: .fullText(tokenizer: .standard))
    try VectorField(
        "embedding",
        type: .float32,
        dimensions: 384,
        index: .hnsw(metric: .cosine)
    )
}

let collection = try Collection.create(
    at: URL(filePath: "./articles.zvec"),
    schema: schema
)
```

The package supports Apple Silicon macOS 13+, arm64 iOS 16+ devices, and
arm64 iOS 16+ simulators. Vamana/DiskANN and indexed sparse-vector fields are
rejected on Apple platforms because Zvec v0.5.1 does not provide a safe native
implementation there. Sparse-vector brute-force queries remain available.

## Topics

### Runtime and collections

- ``ZvecRuntime``
- ``Configuration``
- ``Collection``
- ``CollectionOptions``
- ``CollectionStatistics``
- ``ZvecRuntime/nativeVersion``

### Schemas and values

- ``CollectionSchema``
- ``FieldSchema``
- ``SchemaBuilder``
- ``Document``
- ``DocumentFetchResult``
- ``ZvecValue``
- ``DataType``
- ``SparseVector``

### Queries

- ``VectorQuery``
- ``VectorQuerySource``
- ``FullTextQuery``
- ``FullTextExpression``
- ``BrowseQuery``
- ``BrowseResult``
- ``GroupByVectorQuery``
- ``MultiQuery``
- ``SubQuery``
- ``Reranker``

### Errors

- ``ZvecError``
