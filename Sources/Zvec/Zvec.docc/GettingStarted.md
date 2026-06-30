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

_ = try collection.upsert([
    Document(id: "doc-1", fields: [
        "title": .string("Swift bindings"),
        "embedding": .vectorFloat32([0.1, 0.2, 0.3, 0.4]),
    ])
])

let matches = try collection.query(VectorQuery(
    field: "embedding",
    vector: .float32([0.1, 0.2, 0.3, 0.4]),
    topK: 10,
    outputFields: ["title"]
))
```

Every database operation also has an `async` overload. Async calls execute
native work away from Swift's cooperative executor and check cancellation
before dispatch and after the native call returns.
