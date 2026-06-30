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

