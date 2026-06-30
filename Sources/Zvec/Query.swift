import Foundation

public struct HNSWQueryParameters: Sendable, Equatable {
    public var efSearch: Int
    public var radius: Float?
    public var linearSearch: Bool
    public var useRefiner: Bool

    public init(
        efSearch: Int = 50,
        radius: Float? = nil,
        linearSearch: Bool = false,
        useRefiner: Bool = false
    ) {
        self.efSearch = efSearch
        self.radius = radius
        self.linearSearch = linearSearch
        self.useRefiner = useRefiner
    }
}

public struct IVFQueryParameters: Sendable, Equatable {
    public var probeCount: Int
    public var scaleFactor: Float
    public var radius: Float?
    public var linearSearch: Bool
    public var useRefiner: Bool

    public init(
        probeCount: Int = 10,
        scaleFactor: Float = 1,
        radius: Float? = nil,
        linearSearch: Bool = false,
        useRefiner: Bool = false
    ) {
        self.probeCount = probeCount
        self.scaleFactor = scaleFactor
        self.radius = radius
        self.linearSearch = linearSearch
        self.useRefiner = useRefiner
    }
}

public struct FlatQueryParameters: Sendable, Equatable {
    public var scaleFactor: Float
    public var radius: Float?
    public var linearSearch: Bool
    public var useRefiner: Bool

    public init(
        scaleFactor: Float = 1,
        radius: Float? = nil,
        linearSearch: Bool = false,
        useRefiner: Bool = false
    ) {
        self.scaleFactor = scaleFactor
        self.radius = radius
        self.linearSearch = linearSearch
        self.useRefiner = useRefiner
    }
}

public struct VamanaQueryParameters: Sendable, Equatable {
    public var efSearch: Int
    public var radius: Float?
    public var linearSearch: Bool
    public var useRefiner: Bool

    public init(
        efSearch: Int = 100,
        radius: Float? = nil,
        linearSearch: Bool = false,
        useRefiner: Bool = false
    ) {
        self.efSearch = efSearch
        self.radius = radius
        self.linearSearch = linearSearch
        self.useRefiner = useRefiner
    }
}

public struct FullTextQueryParameters: Sendable, Equatable {
    public enum DefaultOperator: String, Sendable, Equatable {
        case and
        case or
    }

    public var defaultOperator: DefaultOperator

    public init(defaultOperator: DefaultOperator = .or) {
        self.defaultOperator = defaultOperator
    }
}

public enum IndexQueryParameters: Sendable, Equatable {
    case hnsw(HNSWQueryParameters)
    case ivf(IVFQueryParameters)
    case flat(FlatQueryParameters)
    case vamana(VamanaQueryParameters)
}

public struct FullTextQuery: Sendable, Equatable {
    public var field: String
    public var query: String
    public var topK: Int
    public var filter: String?
    public var outputFields: [String]
    public var parameters: FullTextQueryParameters

    public init(
        field: String,
        query: String,
        topK: Int = 10,
        filter: String? = nil,
        outputFields: [String] = [],
        parameters: FullTextQueryParameters = .init()
    ) {
        self.field = field
        self.query = query
        self.topK = topK
        self.filter = filter
        self.outputFields = outputFields
        self.parameters = parameters
    }
}

public struct VectorQuery: Sendable, Equatable {
    public var field: String
    public var vector: DenseQueryVector
    public var topK: Int
    public var filter: String?
    public var includeVector: Bool
    public var outputFields: [String]
    public var indexParameters: IndexQueryParameters?

    public init(
        field: String,
        vector: DenseQueryVector,
        topK: Int,
        filter: String? = nil,
        includeVector: Bool = false,
        outputFields: [String] = [],
        indexParameters: IndexQueryParameters? = nil
    ) {
        self.field = field
        self.vector = vector
        self.topK = topK
        self.filter = filter
        self.includeVector = includeVector
        self.outputFields = outputFields
        self.indexParameters = indexParameters
    }
}

public struct GroupByVectorQuery: Sendable, Equatable {
    public var vectorQuery: VectorQuery
    public var groupByField: String
    public var groupCount: UInt32
    public var groupTopK: UInt32

    public init(
        vectorQuery: VectorQuery,
        groupByField: String,
        groupCount: UInt32,
        groupTopK: UInt32
    ) {
        self.vectorQuery = vectorQuery
        self.groupByField = groupByField
        self.groupCount = groupCount
        self.groupTopK = groupTopK
    }
}

public enum SubQueryPayload: Sendable, Equatable {
    case dense(DenseQueryVector)
    case sparseFloat32(SparseVector<Float>)
    case fullText(String)
}

public struct SubQuery: Sendable, Equatable {
    public var field: String
    public var payload: SubQueryPayload
    public var topK: Int
    public var indexParameters: IndexQueryParameters?
    public var fullTextParameters: FullTextQueryParameters?

    public init(
        field: String,
        payload: SubQueryPayload,
        topK: Int,
        indexParameters: IndexQueryParameters? = nil,
        fullTextParameters: FullTextQueryParameters? = nil
    ) {
        self.field = field
        self.payload = payload
        self.topK = topK
        self.indexParameters = indexParameters
        self.fullTextParameters = fullTextParameters
    }
}

public enum Reranker: Sendable, Equatable {
    case reciprocalRankFusion(rankConstant: UInt32 = 60)
    case weighted([Float])
}

public struct MultiQuery: Sendable, Equatable {
    public var queries: [SubQuery]
    public var topK: Int
    public var filter: String?
    public var includeVector: Bool
    public var outputFields: [String]
    public var reranker: Reranker

    public init(
        queries: [SubQuery],
        topK: Int,
        filter: String? = nil,
        includeVector: Bool = false,
        outputFields: [String] = [],
        reranker: Reranker = .reciprocalRankFusion()
    ) {
        self.queries = queries
        self.topK = topK
        self.filter = filter
        self.includeVector = includeVector
        self.outputFields = outputFields
        self.reranker = reranker
    }
}
