import Foundation
import Zvec

do {
    try ZvecRuntime.initialize()
    defer { try? ZvecRuntime.shutdown() }

    let schema = try CollectionSchema("example") {
        try VectorField(
            "embedding",
            type: .float32,
            dimensions: 4,
            index: .hnsw(metric: .cosine)
        )
        try Field("title", type: .string)
    }

    let path = FileManager.default.temporaryDirectory
        .appending(path: "zvec-swift-example-\(UUID().uuidString)")
    let collection = try Collection.create(at: path, schema: schema)
    defer {
        try? collection.destroy()
        try? FileManager.default.removeItem(at: path)
    }

    try collection.insert([
        Document(
            id: "doc-1",
            fields: [
                "title": .string("hello"),
                "embedding": .vectorFloat32([0.1, 0.2, 0.3, 0.4]),
            ]),
        Document(
            id: "doc-2",
            fields: [
                "title": .string("world"),
                "embedding": .vectorFloat32([0.2, 0.3, 0.4, 0.1]),
            ]),
    ])

    let results = try collection.query(
        VectorQuery(
            field: "embedding",
            vector: .float32([0.4, 0.3, 0.3, 0.1]),
            topK: 10,
            outputFields: ["title"]
        ))
    for result in results {
        print("\(result.id) score=\(result.score ?? 0) title=\(String(describing: result["title"]))")
    }
} catch {
    fputs("zvec-example failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
