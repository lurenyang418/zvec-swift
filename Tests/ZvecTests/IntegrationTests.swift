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
            Document(
                id: "one",
                fields: [
                    "title": .string("first"),
                    "rank": .int64(1),
                    "embedding": .vectorFloat32([1, 0, 0, 0]),
                ]),
            Document(
                id: "two",
                fields: [
                    "title": .string("second"),
                    "rank": .int64(2),
                    "embedding": .vectorFloat32([0, 1, 0, 0]),
                ]),
        ])
        #expect(summary == WriteSummary(succeeded: 2, failed: 0))

        let fetched = try collection.fetch(ids: ["one"], outputFields: ["title", "rank"])
        #expect(fetched.count == 1)
        #expect(fetched[0]["title"] == .string("first"))

        let hits = try collection.query(
            VectorQuery(
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
        let collection = try await Collection.create(at: path, schema: schema)
        defer { try? collection.destroy() }

        let summary = try await collection.insert([
            Document(id: "one", fields: ["embedding": .vectorFloat32([1, 0])])
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
            Document(
                id: "one",
                fields: [
                    "category": .string("a"),
                    "flags": .arrayBool([true, false, true, true, false]),
                    "blobs": .arrayBinary(firstBlobs),
                    "embedding": .vectorFloat32([1, 0]),
                ]),
            Document(
                id: "two",
                fields: [
                    "category": .string("a"),
                    "flags": .arrayBool([false, true]),
                    "blobs": .arrayBinary([Data([9])]),
                    "embedding": .vectorFloat32([0.9, 0.1]),
                ]),
            Document(
                id: "three",
                fields: [
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
        let groups = try collection.query(
            GroupByVectorQuery(
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

    @Test func bundledJiebaFullTextQuery() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("jieba") {
            try Field("title", type: .string, index: .fullText(tokenizer: .jieba))
            try VectorField("embedding", type: .float32, dimensions: 2, index: .hnsw())
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-jieba-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer {
            try? collection.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        _ = try collection.insert([
            Document(
                id: "swift",
                fields: [
                    "title": .string("Swift 向量数据库桥接"),
                    "embedding": .vectorFloat32([1, 0]),
                ]),
            Document(
                id: "weather",
                fields: [
                    "title": .string("上海今天有阵雨"),
                    "embedding": .vectorFloat32([0, 1]),
                ]),
        ])
        try collection.flush()

        let hits = try collection.query(
            FullTextQuery(
                field: "title",
                query: "向量 数据库",
                topK: 2,
                outputFields: ["title"],
                parameters: .init(defaultOperator: .and)
            ))
        #expect(hits.map(\.id) == ["swift"])

        let hybrid = try collection.query(
            MultiQuery(
                queries: [
                    SubQuery(field: "embedding", payload: .dense(.float32([1, 0])), topK: 2),
                    SubQuery(field: "title", payload: .fullText("数据库"), topK: 2),
                ],
                topK: 2,
                outputFields: ["title"],
                reranker: .weighted([0.4, 0.6])
            ))
        #expect(hybrid.first?.id == "swift")
    }

    @Test func browseAdvancedFullTextAndQueryByDocumentID() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("core-query-extensions") {
            try Field("title", type: .string, index: .fullText())
            try Field("rank", type: .int64, index: .inverted())
            try VectorField("embedding", type: .float32, dimensions: 2, index: .flat())
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-core-query-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer {
            try? collection.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        #expect(try collection.browse().documents.isEmpty)

        _ = try collection.insert([
            Document(
                id: "swift",
                fields: [
                    "title": .string("swift vector database"),
                    "rank": .int64(3),
                    "embedding": .vectorFloat32([1, 0]),
                ]),
            Document(
                id: "server",
                fields: [
                    "title": .string("swift server"),
                    "rank": .int64(2),
                    "embedding": .vectorFloat32([0.9, 0.1]),
                ]),
            Document(
                id: "weather",
                fields: [
                    "title": .string("weather report"),
                    "rank": .int64(1),
                    "embedding": .vectorFloat32([0, 1]),
                ]),
        ])
        try collection.flush()

        let browsed = try collection.browse(
            BrowseQuery(
                filter: "rank >= 2 AND rank <= 3", limit: 1, outputFields: ["title"]
            )
        )
        #expect(browsed.documents.count == 1)
        #expect(browsed.limitReached)
        #expect(browsed.documents[0]["title"] != nil)
        #expect(browsed.documents[0]["embedding"] == nil)
        let all = try collection.browse(BrowseQuery(limit: 10))
        #expect(all.documents.count == 3)
        #expect(!all.limitReached)
        let withVectors = try collection.browse(
            BrowseQuery(
                filter: "rank >= 1", limit: 10,
                outputFields: ["embedding"], includeVector: true
            )
        )
        #expect(withVectors.documents.allSatisfy { $0["embedding"] != nil })
        #expect(try collection.browse(BrowseQuery(limit: 100_000)).documents.count == 3)
        #expect(throws: ZvecError.self) {
            try collection.browse(BrowseQuery(limit: 0))
        }
        #expect(throws: ZvecError.self) {
            try collection.browse(BrowseQuery(limit: -1))
        }
        #expect(throws: ZvecError.self) {
            try collection.browse(BrowseQuery(limit: 100_001))
        }
        do {
            _ = try collection.browse(BrowseQuery(filter: "missing_field = 1"))
            Issue.record("An invalid Browse filter unexpectedly succeeded")
        } catch let error {
            #expect(!error.message.isEmpty)
        }
        let advanced = try collection.query(
            FullTextQuery(
                field: "title",
                expression: .query("+swift -database"),
                topK: 3,
                outputFields: ["title"]
            )
        )
        #expect(advanced.map(\.id) == ["server"])
        let byID = try collection.query(
            VectorQuery(field: "embedding", documentID: "swift", topK: 3)
        )
        #expect(byID.first?.id == "swift")
        let byVector = try collection.query(
            VectorQuery(field: "embedding", vector: .float32([1, 0]), topK: 3)
        )
        #expect(byID.map(\.id) == byVector.map(\.id))
        #expect(throws: ZvecError.self) {
            try collection.query(VectorQuery(field: "title", documentID: "swift", topK: 3))
        }
        #expect(throws: ZvecError.self) {
            try collection.query(
                VectorQuery(field: "embedding", documentID: "missing", topK: 3)
            )
        }

        let nullableSchema = try CollectionSchema("nullable-vector") {
            try VectorField("embedding", type: .float32, dimensions: 2, nullable: true)
        }
        let nullablePath = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-null-vector-\(UUID().uuidString)")
        let nullableCollection = try Collection.create(at: nullablePath, schema: nullableSchema)
        defer {
            try? nullableCollection.destroy()
            try? FileManager.default.removeItem(at: nullablePath)
        }
        _ = try nullableCollection.insert(Document(id: "no-vector"))
        do {
            _ = try nullableCollection.query(
                VectorQuery(field: "embedding", documentID: "no-vector", topK: 3)
            )
            Issue.record("Query by ID unexpectedly accepted a missing source vector")
        } catch let error {
            #expect(error.code == .failedPrecondition)
        }
    }

    @Test func singleDocumentConveniencesFetchResultsAndIntrospection() async throws {
        try await ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("conveniences") {
            try Field("value", type: .int64)
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-conveniences-\(UUID().uuidString)")
        let collection = try await Collection.create(at: path, schema: schema)
        defer { try? FileManager.default.removeItem(at: path) }

        #expect(collection.location == path.standardizedFileURL.resolvingSymlinksInPath())
        #expect(!collection.isClosed)
        let inserted = try await collection.insert(
            Document(id: "one", fields: ["value": .int64(1)])
        )
        #expect(inserted.succeeded)
        let updated = try await collection.update(
            Document(id: "one", fields: ["value": .int64(2)])
        )
        #expect(updated.succeeded)
        #expect(try await collection.fetch(id: "one")?["value"] == .int64(2))

        let results = try await collection.fetchResults(ids: ["one", "missing", "one"])
        #expect(results.map(\.id) == ["one", "missing", "one"])
        #expect(results[0].document?.id == "one")
        #expect(results[1].document == nil)
        #expect(results[2].document?.id == "one")

        let syncBrowse: () throws(ZvecError) -> BrowseResult = {
            try collection.browse(BrowseQuery(filter: "value = 2", limit: 10))
        }
        let syncBrowsed = try syncBrowse()
        let browsed = try await collection.browse(BrowseQuery(filter: "value = 2", limit: 10))
        #expect(browsed == syncBrowsed)
        #expect(browsed.documents.map(\.id) == ["one"])

        let deleted = try await collection.delete(id: "one")
        #expect(deleted.succeeded)
        try await collection.close()
        #expect(collection.isClosed)
        do {
            _ = try await collection.browse()
            Issue.record("A closed collection unexpectedly accepted Browse")
        } catch let error {
            #expect(error.code == .closed)
        }
    }

    @Test func sparseAndDenseMultiQuery() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("sparse-multi") {
            try VectorField("dense", type: .float32, dimensions: 2, index: .hnsw())
            try Field("sparse", type: .sparseVectorFloat32)
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-sparse-\(UUID().uuidString)")
        let collection = try Collection.create(at: path, schema: schema)
        defer {
            try? collection.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        let near = try SparseVector(indices: [1, 5], values: [1, 0.5] as [Float])
        let far = try SparseVector(indices: [2, 9], values: [1, 0.5] as [Float])
        _ = try collection.insert([
            Document(
                id: "near",
                fields: [
                    "dense": .vectorFloat32([1, 0]),
                    "sparse": .sparseVectorFloat32(near),
                ]),
            Document(
                id: "far",
                fields: [
                    "dense": .vectorFloat32([0, 1]),
                    "sparse": .sparseVectorFloat32(far),
                ]),
        ])

        let hits = try collection.query(
            MultiQuery(
                queries: [
                    SubQuery(field: "dense", payload: .dense(.float32([1, 0])), topK: 2),
                    SubQuery(field: "sparse", payload: .sparseFloat32(near), topK: 2),
                ],
                topK: 2,
                reranker: .reciprocalRankFusion()
            ))
        #expect(hits.first?.id == "near")
    }

    @Test func detailedWritesSchemaEvolutionAndReopen() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("evolution", maximumDocumentsPerSegment: 2_000) {
            try Field("rank", type: .int64)
        }
        let options = CollectionOptions(
            enableMemoryMapping: false,
            maximumBufferSize: 1_048_576,
            readOnly: false
        )
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-evolution-\(UUID().uuidString)")
        var collection: Collection? = try Collection.create(
            at: path, schema: schema, options: options
        )
        defer {
            try? collection?.destroy()
            try? FileManager.default.removeItem(at: path)
        }

        #expect(try collection?.options() == options)
        let inserted = try collection?.insertWithResults([
            Document(id: "one", fields: ["rank": .int64(1)])
        ])
        #expect(inserted?.first?.succeeded == true)
        let missing = try collection?.updateWithResults([
            Document(id: "missing", fields: ["rank": .int64(2)])
        ])
        #expect(missing?.first?.succeeded == false)

        try collection?.addColumn(try Field("priority", type: .int32, nullable: true))
        try collection?.alterColumn("priority", newName: "weight")
        try collection?.createIndex(.inverted(), for: "rank")
        #expect(collection?.schema.field(named: "weight") != nil)
        try collection?.dropIndex(for: "rank")
        try collection?.dropColumn("weight")

        try collection?.close()
        try collection?.close()
        collection = try Collection.open(at: path, options: options)
        #expect(collection?.location == path.standardizedFileURL.resolvingSymlinksInPath())
        #expect(collection?.isClosed == false)
        #expect(collection?.schema.maximumDocumentsPerSegment == 2_000)
        #expect(try collection?.fetch(ids: ["one"]).first?.id == "one")
        try collection?.delete(where: "rank = 1")
        #expect(try collection?.statistics().documentCount == 0)
    }

    @Test func concurrentReadsAndCloseAreRaceFree() async throws {
        try await ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let schema = try CollectionSchema("concurrency") {
            try Field("value", type: .int64)
        }
        let path = FileManager.default.temporaryDirectory
            .appending(path: "zvec-swift-concurrency-\(UUID().uuidString)")
        let collection = try await Collection.create(at: path, schema: schema)
        defer { try? FileManager.default.removeItem(at: path) }
        _ = try await collection.insert(
            (0..<32).map {
                Document(id: "doc-\($0)", fields: ["value": .int64(Int64($0))])
            })

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    _ = try? await collection.fetch(ids: ["doc-\(index)"])
                }
            }
            group.addTask { try? await collection.close() }
        }

        do {
            _ = try await collection.statistics()
            Issue.record("A closed collection unexpectedly accepted an operation")
        } catch let error {
            #expect(error.code == .closed)
        }
    }

    @Test func everyValueTypeRoundTripsThroughNativeSerialization() throws {
        try ZvecRuntime.initialize()
        defer { try? ZvecRuntime.shutdown() }

        let scalarFields: [(String, DataType)] = [
            ("binary", .binary), ("string", .string), ("bool", .bool),
            ("int32", .int32), ("int64", .int64), ("uint32", .uint32),
            ("uint64", .uint64), ("float", .float), ("double", .double),
            ("arrayBinary", .arrayBinary), ("arrayString", .arrayString),
            ("arrayBool", .arrayBool), ("arrayInt32", .arrayInt32),
            ("arrayInt64", .arrayInt64), ("arrayUInt32", .arrayUInt32),
            ("arrayUInt64", .arrayUInt64), ("arrayFloat", .arrayFloat),
            ("arrayDouble", .arrayDouble),
        ]
        var fields = try scalarFields.map { try Field($0.0, type: $0.1) }
        fields += [
            try VectorField("binary32", type: .binary32, dimensions: 32, index: .flat()),
            try VectorField("binary64", type: .binary64, dimensions: 64, index: .flat()),
            try VectorField("float16Vector", type: .float16, dimensions: 2, index: .flat()),
            try VectorField("float32Vector", type: .float32, dimensions: 2, index: .flat()),
            try VectorField("float64Vector", type: .float64, dimensions: 2, index: .flat()),
            try VectorField("int4Vector", type: .int4, dimensions: 3, index: .flat()),
            try VectorField("int8Vector", type: .int8, dimensions: 2, index: .flat()),
            try VectorField("int16Vector", type: .int16, dimensions: 2, index: .flat()),
            try Field("sparse16", type: .sparseVectorFloat16),
            try Field("sparse32", type: .sparseVectorFloat32),
        ]
        let schema = try CollectionSchema(name: "all-values", fields: fields)
        let sparse16 = try SparseVector(
            indices: [1, 7], values: [Float16(1.5), Float16(2.5)]
        )
        let sparse32 = try SparseVector(indices: [2, 8], values: [3.5, 4.5] as [Float])
        let values: [String: ZvecValue] = [
            "binary": .binary(Data([0, 255, 0, 7])),
            "string": .string("Swift 中文 " + String(UnicodeScalar(0)) + " suffix"),
            "bool": .bool(true),
            "int32": .int32(-32), "int64": .int64(-64),
            "uint32": .uint32(32), "uint64": .uint64(64),
            "float": .float(1.25), "double": .double(2.5),
            "arrayBinary": .arrayBinary([Data([0, 1]), Data(), Data([255])]),
            "arrayString": .arrayString(["a", "中文", ""]),
            "arrayBool": .arrayBool([true, false, true, false, true, false, true, false, true]),
            "arrayInt32": .arrayInt32([-1, 2]),
            "arrayInt64": .arrayInt64([-3, 4]),
            "arrayUInt32": .arrayUInt32([5, 6]),
            "arrayUInt64": .arrayUInt64([7, 8]),
            "arrayFloat": .arrayFloat([1.5, 2.5]),
            "arrayDouble": .arrayDouble([3.5, 4.5]),
            "binary32": .vectorBinary32(Data([1, 2, 3, 4])),
            "binary64": .vectorBinary64(Data([1, 2, 3, 4, 5, 6, 7, 8])),
            "float16Vector": .vectorFloat16([1, 2]),
            "float32Vector": .vectorFloat32([3, 4]),
            "float64Vector": .vectorFloat64([5, 6]),
            "int4Vector": .vectorInt4(try PackedInt4Vector(bytes: Data([0x12, 0x03]), dimensions: 3)),
            "int8Vector": .vectorInt8([-1, 2]),
            "int16Vector": .vectorInt16([-3, 4]),
            "sparse16": .sparseVectorFloat16(sparse16),
            "sparse32": .sparseVectorFloat32(sparse32),
        ]
        let serialized = try Document(id: "all", fields: values).serializedData()
        let decoded = try Document.deserialize(serialized, schema: schema)
        #expect(decoded.fields == values)
        try schema.validate(Document(id: "all", fields: values), for: .insert)
    }
}
