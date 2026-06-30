import Foundation

public struct Document: Sendable, Equatable {
    public var id: String
    public var documentID: UInt64?
    public var score: Float?
    public var operation: DocumentOperation
    public var fields: [String: ZvecValue]

    public init(
        id: String,
        fields: [String: ZvecValue] = [:],
        operation: DocumentOperation = .insert,
        documentID: UInt64? = nil,
        score: Float? = nil
    ) {
        self.id = id
        self.documentID = documentID
        self.score = score
        self.operation = operation
        self.fields = fields
    }

    public subscript(field: String) -> ZvecValue? {
        get { fields[field] }
        set { fields[field] = newValue }
    }

    public func serializedData() throws(ZvecError) -> Data {
        try CAPI.typed { try NativeDocument(self).serialized() }
    }

    public static func deserialize(
        _ data: Data, schema: CollectionSchema
    ) throws(ZvecError) -> Document {
        try CAPI.typed { try NativeDocument(serialized: data).value(schema: schema) }
    }

    public func nativeMemoryUsage() throws(ZvecError) -> Int {
        try CAPI.typed { try NativeDocument(self).memoryUsage() }
    }

    public func nativeDetailDescription() throws(ZvecError) -> String {
        try CAPI.typed { try NativeDocument(self).detailDescription() }
    }

    public func merging(_ other: Document) -> Document {
        var result = self
        result.fields.merge(other.fields) { _, replacement in replacement }
        if !other.id.isEmpty { result.id = other.id }
        if let documentID = other.documentID { result.documentID = documentID }
        if let score = other.score { result.score = score }
        result.operation = other.operation
        return result
    }
}

public struct WriteSummary: Sendable, Equatable {
    public let succeeded: Int
    public let failed: Int

    public init(succeeded: Int, failed: Int) {
        self.succeeded = succeeded
        self.failed = failed
    }
}

public struct DocumentWriteResult: Sendable, Equatable {
    public let id: String
    public let error: ZvecError?

    public var succeeded: Bool { error == nil }

    public init(id: String, error: ZvecError?) {
        self.id = id
        self.error = error
    }
}

public struct GroupResult: Sendable, Equatable {
    public let value: String
    public let documents: [Document]

    public init(value: String, documents: [Document]) {
        self.value = value
        self.documents = documents
    }
}
