# Getting Started

## Add the package

Add `https://github.com/lurenyang418/zvec-swift.git` as a Swift Package and
link the `Zvec` product. The native XCFramework is downloaded automatically
for tagged releases.

## Insert and query

```swift
try ZvecRuntime.initialize()
defer { try? ZvecRuntime.shutdown() }

let collection = try Collection.open(at: databaseURL)
defer { try? collection.close() }

_ = try collection.upsert(Document(id: "doc-1", fields: [
    "title": .string("Swift bindings"),
    "embedding": .vectorFloat32([0.1, 0.2, 0.3, 0.4]),
]))

let matches = try collection.query(VectorQuery(
    field: "embedding",
    vector: .float32([0.1, 0.2, 0.3, 0.4]),
    topK: 10,
    outputFields: ["title"]
))
```

## Browse and query by ID

Use ``BrowseQuery`` for bounded filter-only reads. It is not cursor pagination and does not guarantee result order.

```swift
let page = try collection.browse(BrowseQuery(
    filter: "published = true",
    limit: 50,
    outputFields: ["title"]
))

let related = try collection.query(VectorQuery(
    field: "embedding",
    documentID: "doc-1",
    topK: 10,
    outputFields: ["title"]
))
```

Full-text search distinguishes natural-language matching from advanced expressions:

```swift
let natural = FullTextQuery(field: "title", expression: .match("swift database"))
let advanced = FullTextQuery(field: "title", expression: .query("+swift -server"))
```

Every database operation also has an `async` overload. Async calls execute
native work away from Swift's cooperative executor and check cancellation
before dispatch and after the native call returns.

## Limits and lifetime

- Browse limits are `1...100_000`. A true ``BrowseResult/limitReached`` means additional documents may exist; it is not a continuation token.
- Query `topK` and subquery candidate counts must be positive and fit the native 32-bit range.
- Query and Browse order must not be used as stable pagination order.
- After closing or destroying a ``Collection``, database operations fail with ``ZvecError/Code/closed``. Closing an already closed Collection succeeds.
- Vamana/DiskANN and indexed sparse-vector fields are unavailable on Apple platforms with Zvec v0.5.1. Float32 sparse payloads remain available through ``MultiQuery``.
