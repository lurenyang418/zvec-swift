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

@Test func dataTypeClassificationIsExhaustive() {
    #expect(DataType.string.isScalar)
    #expect(!DataType.arrayString.isScalar)
    #expect(DataType.arrayString.isArray)
    #expect(DataType.vectorFloat32.isDenseVector)
    #expect(DataType.sparseVectorFloat32.isSparseVector)
    #expect(DataType.vectorInt4.requiresDimensions)
    #expect(!DataType.sparseVectorFloat16.requiresDimensions)
    #expect(!DataType.undefined.isVector)
}

@Test func structuredNativeVersionMatchesVersionString() {
    let version = ZvecRuntime.nativeVersion
    #expect(version.major == 0)
    #expect(version.minor == 5)
    #expect(version.patch == 1)
    #expect(ZvecVersion(major: 0, minor: 5, patch: 1) < ZvecVersion(major: 0, minor: 6, patch: 0))
    #expect(ZvecRuntime.version.contains(version.description))
}

@Test func schemaValidatesDocumentsWithoutReplacingNativeValidation() throws {
    let schema = try CollectionSchema("validation") {
        try Field("title", type: .string)
        try Field("subtitle", type: .string, nullable: true)
        try VectorField("embedding", type: .float32, dimensions: 2)
        try VectorField("bits", type: .binary32, dimensions: 32)
    }
    try schema.validate(
        Document(
            id: "valid",
            fields: [
                "title": .string("Swift"),
                "subtitle": .null,
                "embedding": .vectorFloat32([1, 0]),
                "bits": .vectorBinary32(Data([0, 1, 2, 3])),
            ]
        ),
        for: .insert
    )
    #expect(throws: ZvecError.self) {
        try schema.validate(Document(id: "", fields: [:]), for: .insert)
    }
    #expect(throws: ZvecError.self) {
        try schema.validate(Document(id: "bad", fields: ["missing": .string("x")]), for: .update)
    }
    #expect(throws: ZvecError.self) {
        try schema.validate(Document(id: "bad", fields: ["title": .null]), for: .upsert)
    }
    #expect(throws: ZvecError.self) {
        try schema.validate(
            Document(id: "bad", fields: ["embedding": .vectorFloat32([1])]),
            for: .insert
        )
    }
}

@Test func rejectsInvalidNativeIntegerRanges() throws {
    #expect(throws: ZvecError.self) {
        _ = try CAPI.int32(Int.max, named: "topK")
    }
    #expect(throws: ZvecError.self) {
        _ = try CAPI.int32(Int.min, named: "topK")
    }
    #expect(throws: ZvecError.self) {
        _ = try CAPI.int32(UInt32.max, named: "rankConstant")
    }
    #expect(try CAPI.int32(Int(Int32.max), named: "topK") == Int32.max)
}

@Test func throwingNativeQueryInitializersReleaseHandlesExactlyOnce() {
    #expect(throws: ZvecError.self) {
        _ = try NativeBrowseQuery(BrowseQuery(limit: 0))
    }
    #expect(throws: ZvecError.self) {
        _ = try NativeBrowseQuery(BrowseQuery(limit: 100_001))
    }
    #expect(throws: ZvecError.self) {
        _ = try NativeFTS(.match("  \n"))
    }
    #expect(throws: ZvecError.self) {
        _ = try NativeFTS(.query(""))
    }
}

@Test func rejectsZeroThreadCountsBeforeCallingNative() {
    #expect(throws: ZvecError.self) {
        try Configuration(queryThreadCount: 0).validate()
    }
    #expect(throws: ZvecError.self) {
        try Configuration(optimizeThreadCount: 0).validate()
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
