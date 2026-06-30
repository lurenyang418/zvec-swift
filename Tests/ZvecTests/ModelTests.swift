import Foundation
import Testing

@testable import Zvec

@Test func schemaBuilderCreatesEquivalentSchema() throws {
    let built = try CollectionSchema("docs") {
        try Field("title", type: .string, nullable: true)
        try VectorField("embedding", type: .float32, dimensions: 4, index: .hnsw())
    }
    let direct = try CollectionSchema(
        name: "docs",
        fields: [
            try FieldSchema("title", type: .string, nullable: true),
            try FieldSchema(
                "embedding",
                type: .vectorFloat32,
                dimensions: 4,
                index: .hnsw()
            ),
        ])
    #expect(built == direct)
}

@Test func rejectsDuplicateFields() {
    #expect(throws: ZvecError.self) {
        try CollectionSchema(
            name: "docs",
            fields: [
                try FieldSchema("title", type: .string),
                try FieldSchema("title", type: .string),
            ])
    }
}

@Test func validatesSparseVector() throws {
    let vector = try SparseVector(indices: [1, 3, 8], values: [1.0, 2.0, 3.0] as [Float])
    #expect(vector.indices == [1, 3, 8])
    #expect(throws: ZvecError.self) {
        try SparseVector(indices: [1, 1], values: [1.0, 2.0] as [Float])
    }
    #expect(throws: ZvecError.self) {
        try SparseVector(indices: [1], values: [1.0, 2.0] as [Float])
    }
}

@Test func rejectsUnsafeIndexedSparseFieldOnApple() {
    #if os(macOS) || os(iOS)
        #expect(throws: ZvecError.self) {
            try FieldSchema("sparse", type: .sparseVectorFloat32, index: .hnsw())
        }
    #endif
}

@Test func validatesPackedInt4Length() throws {
    let vector = try PackedInt4Vector(bytes: Data([0x12, 0x30]), dimensions: 3)
    #expect(vector.dimensions == 3)
    #expect(throws: ZvecError.self) {
        try PackedInt4Vector(bytes: Data([0x12]), dimensions: 3)
    }
}

@Test func documentNativeUtilitiesRoundTrip() throws {
    let schema = try CollectionSchema("serialization") {
        try Field("title", type: .string)
        try Field("flags", type: .arrayBool)
        try VectorField("embedding", type: .float32, dimensions: 2)
    }
    let document = Document(
        id: "one",
        fields: [
            "title": .string("Swift"),
            "flags": .arrayBool([true, false, true]),
            "embedding": .vectorFloat32([1, 0]),
        ])

    let data = try document.serializedData()
    let decoded = try Document.deserialize(data, schema: schema)
    #expect(decoded.id == document.id)
    #expect(decoded.fields == document.fields)
    #expect(try document.nativeMemoryUsage() > 0)
    #expect(try document.nativeDetailDescription().contains("Swift"))

    let merged = document.merging(Document(id: "", fields: ["title": .string("Updated")]))
    #expect(merged.id == "one")
    #expect(merged["title"] == .string("Updated"))
}
