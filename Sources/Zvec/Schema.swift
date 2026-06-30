import Foundation

public enum FullTextTokenizer: Sendable, Equatable {
    case standard
    case whitespace
    case jieba

    var nativeName: String {
        switch self {
        case .standard: "standard"
        case .whitespace: "whitespace"
        case .jieba: "jieba"
        }
    }
}

public enum IndexConfiguration: Sendable, Equatable {
    case hnsw(
        metric: Metric = .cosine,
        quantization: Quantization = .none,
        m: Int = 16,
        efConstruction: Int = 200
    )
    case ivf(
        metric: Metric = .cosine,
        quantization: Quantization = .none,
        listCount: Int = 1_024,
        iterations: Int = 10,
        useSOAR: Bool = false
    )
    case flat(metric: Metric = .cosine, quantization: Quantization = .none)
    case vamana(
        metric: Metric = .cosine,
        maxDegree: Int = 64,
        buildListSize: Int = 100,
        alpha: Float = 1.2
    )
    case inverted(enableRangeOptimization: Bool = true, enableWildcard: Bool = false)
    case fullText(
        tokenizer: FullTextTokenizer = .standard,
        tokenFilters: [String] = [],
        options: [String: String] = [:]
    )
}

public struct FieldSchema: Sendable, Equatable {
    public var name: String
    public var dataType: DataType
    public var nullable: Bool
    public var dimensions: Int
    public var index: IndexConfiguration?

    public init(
        _ name: String,
        type: DataType,
        nullable: Bool = false,
        dimensions: Int = 0,
        index: IndexConfiguration? = nil
    ) throws(ZvecError) {
        guard !name.isEmpty else { throw .invalid("Field name must not be empty") }
        if type.isVector && ![.sparseVectorFloat16, .sparseVectorFloat32].contains(type) {
            guard dimensions > 0 else { throw .invalid("Dense vector fields require positive dimensions") }
        } else if dimensions != 0 {
            throw .invalid("Only dense vector fields accept dimensions")
        }
        #if os(macOS) || os(iOS)
            if [.sparseVectorFloat16, .sparseVectorFloat32].contains(type), index != nil {
                throw ZvecError(
                    code: .notSupported,
                    message:
                        "Indexed sparse-vector fields are unsafe in Zvec 0.5.1 on Apple platforms; use brute-force sparse queries"
                )
            }
        #endif
        self.name = name
        self.dataType = type
        self.nullable = nullable
        self.dimensions = dimensions
        self.index = index
    }
}

public enum VectorElementType: Sendable {
    case binary32
    case binary64
    case float16
    case float32
    case float64
    case int4
    case int8
    case int16

    var dataType: DataType {
        switch self {
        case .binary32: .vectorBinary32
        case .binary64: .vectorBinary64
        case .float16: .vectorFloat16
        case .float32: .vectorFloat32
        case .float64: .vectorFloat64
        case .int4: .vectorInt4
        case .int8: .vectorInt8
        case .int16: .vectorInt16
        }
    }
}

@resultBuilder
public enum SchemaBuilder {
    public static func buildBlock(_ components: FieldSchema...) -> [FieldSchema] { components }
    public static func buildArray(_ components: [[FieldSchema]]) -> [FieldSchema] { components.flatMap(\.self) }
    public static func buildOptional(_ component: [FieldSchema]?) -> [FieldSchema] { component ?? [] }
    public static func buildEither(first component: [FieldSchema]) -> [FieldSchema] { component }
    public static func buildEither(second component: [FieldSchema]) -> [FieldSchema] { component }
    public static func buildExpression(_ expression: FieldSchema) -> [FieldSchema] { [expression] }
    public static func buildPartialBlock(first: [FieldSchema]) -> [FieldSchema] { first }
    public static func buildPartialBlock(
        accumulated: [FieldSchema], next: [FieldSchema]
    ) -> [FieldSchema] { accumulated + next }
}

public struct CollectionSchema: Sendable, Equatable {
    public var name: String
    public var fields: [FieldSchema]
    public var maximumDocumentsPerSegment: UInt64

    public init(
        name: String,
        fields: [FieldSchema],
        maximumDocumentsPerSegment: UInt64 = 10_000_000
    ) throws(ZvecError) {
        guard !name.isEmpty else { throw .invalid("Collection name must not be empty") }
        let names = Set(fields.map(\.name))
        guard names.count == fields.count else { throw .invalid("Schema field names must be unique") }
        guard maximumDocumentsPerSegment >= 1_000 else {
            throw .invalid("maximumDocumentsPerSegment must be at least 1,000")
        }
        self.name = name
        self.fields = fields
        self.maximumDocumentsPerSegment = maximumDocumentsPerSegment
    }

    public init(
        _ name: String,
        maximumDocumentsPerSegment: UInt64 = 10_000_000,
        @SchemaBuilder fields: () throws -> [FieldSchema]
    ) throws(ZvecError) {
        let fields = try CAPI.typed { try fields() }
        try self.init(
            name: name,
            fields: fields,
            maximumDocumentsPerSegment: maximumDocumentsPerSegment
        )
    }

    public func field(named name: String) -> FieldSchema? {
        fields.first { $0.name == name }
    }
}

public func Field(
    _ name: String,
    type: DataType,
    nullable: Bool = false,
    index: IndexConfiguration? = nil
) throws(ZvecError) -> FieldSchema {
    try FieldSchema(name, type: type, nullable: nullable, index: index)
}

public func VectorField(
    _ name: String,
    type: VectorElementType,
    dimensions: Int,
    nullable: Bool = false,
    index: IndexConfiguration? = nil
) throws(ZvecError) -> FieldSchema {
    try FieldSchema(name, type: type.dataType, nullable: nullable, dimensions: dimensions, index: index)
}
