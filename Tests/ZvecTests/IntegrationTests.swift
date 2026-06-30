import Foundation
import Testing
@testable import Zvec

@Suite(.serialized)
struct IntegrationTests {
    @Test func lifecycleCRUDAndVectorQuery() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("integration") {
            try Field("title", type: .string)
            try Field("rank", type: .int64, index: .inverted())
            try VectorField("embedding", type: .float32, dimensions: 4, index: .hnsw())
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-tests-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer {
            try? collection.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        let summary = try collection.insert([
            Document(id: "one", fields: [
                "title": .string("first"),
                "rank": .int64(1),
                "embedding": .vectorFloat32([1, 0, 0, 0]),
            ]),
            Document(id: "two", fields: [
                "title": .string("second"),
                "rank": .int64(2),
                "embedding": .vectorFloat32([0, 1, 0, 0]),
            ]),
        ])
        #expect(summary == WriteSummary(succeeded: 2, failed: 0))

        let fetched = try collection.fetch(ids: ["one"], outputFields: ["title", "rank"])
        #expect(fetched.count == 1)
        #expect(fetched[0]["title"] == .string("first"))

        let hits = try collection.query(VectorQuery(
            field: "embedding",
            vector: .float32([1, 0, 0, 0]),
            topK: 2,
            outputFields: ["title"]
        ))
        #expect(hits.first?.id == "one")

        let deleted = try collection.delete(ids: ["two"])
        #expect(deleted.succeeded == 1)
        #expect(try collection.statistics().documentCount == 1)
    }

    @Test func asyncAPIUsesSameSemantics() async throws {
        try await ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("async") {
            try VectorField("embedding", type: .float32, dimensions: 2, index: .hnsw())
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-async-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer { try? collection.destroy() }

        let summary = try await collection.insert([
            Document(id: "one", fields: ["embedding": .vectorFloat32([1, 0])]),
        ])
        #expect(summary.succeeded == 1)
        let values = try await collection.fetch(ids: ["one"], includeVector: true)
        #expect(values.count == 1)
        try await collection.close()
    }

    @Test func arrayRoundTripAndGroupByQuery() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("arrays-and-groups") {
            try Field("category", type: .string, index: .inverted())
            try Field("flags", type: .arrayBool)
            try Field("blobs", type: .arrayBinary)
            try VectorField("embedding", type: .float32, dimensions: 2, index: .flat())
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-group-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer {
            try? collection.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        let firstBlobs = [Data([0, 1, 2]), Data(), Data([255, 7])]
        let summary = try collection.insert([
            Document(id: "one", fields: [
                "category": .string("a"),
                "flags": .arrayBool([true, false, true, true, false]),
                "blobs": .arrayBinary(firstBlobs),
                "embedding": .vectorFloat32([1, 0]),
            ]),
            Document(id: "two", fields: [
                "category": .string("a"),
                "flags": .arrayBool([false, true]),
                "blobs": .arrayBinary([Data([9])]),
                "embedding": .vectorFloat32([0.9, 0.1]),
            ]),
            Document(id: "three", fields: [
                "category": .string("b"),
                "flags": .arrayBool([]),
                "blobs": .arrayBinary([]),
                "embedding": .vectorFloat32([0, 1]),
            ]),
        ])
        #expect(summary.failed == 0)

        let fetched = try collection.fetch(ids: ["one"], outputFields: ["category", "flags", "blobs"])
        #expect(fetched.first?["category"] == .string("a"))
        #expect(fetched.first?["flags"] == .arrayBool([true, false, true, true, false]))
        #expect(fetched.first?["blobs"] == .arrayBinary(firstBlobs))

        try collection.flush()
        try collection.optimize()
        let groups = try collection.query(GroupByVectorQuery(
            vectorQuery: VectorQuery(
                field: "embedding",
                vector: .float32([1, 0]),
                topK: 3,
                outputFields: ["category"]
            ),
            groupByField: "category",
            groupCount: 2,
            groupTopK: 2
        ))
        #expect(Set(groups.map(\.value)) == Set(["a", "b"]))
        #expect(groups.first(where: { $0.value == "a" })?.documents.count == 2)
    }
}
