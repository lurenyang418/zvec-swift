public struct IndexStatistics: Sendable, Equatable {
    public let name: String
    public let completeness: Float

    public init(name: String, completeness: Float) {
        self.name = name
        self.completeness = completeness
    }
}

public struct CollectionStatistics: Sendable, Equatable {
    public let documentCount: UInt64
    public let indexStatistics: [IndexStatistics]

    public init(documentCount: UInt64, indexStatistics: [IndexStatistics]) {
        self.documentCount = documentCount
        self.indexStatistics = indexStatistics
    }
}
