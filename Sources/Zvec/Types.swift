import Foundation

public enum DataType: UInt32, Sendable, CaseIterable {
    case undefined = 0
    case binary = 1
    case string = 2
    case bool = 3
    case int32 = 4
    case int64 = 5
    case uint32 = 6
    case uint64 = 7
    case float = 8
    case double = 9
    case vectorBinary32 = 20
    case vectorBinary64 = 21
    case vectorFloat16 = 22
    case vectorFloat32 = 23
    case vectorFloat64 = 24
    case vectorInt4 = 25
    case vectorInt8 = 26
    case vectorInt16 = 27
    case sparseVectorFloat16 = 30
    case sparseVectorFloat32 = 31
    case arrayBinary = 40
    case arrayString = 41
    case arrayBool = 42
    case arrayInt32 = 43
    case arrayInt64 = 44
    case arrayUInt32 = 45
    case arrayUInt64 = 46
    case arrayFloat = 47
    case arrayDouble = 48

    public var isVector: Bool { (20...31).contains(rawValue) }
    public var isArray: Bool { (40...48).contains(rawValue) }
}

public enum Metric: UInt32, Sendable, CaseIterable {
    case undefined = 0
    case l2 = 1
    case innerProduct = 2
    case cosine = 3
    case mipsL2 = 4
}

public enum Quantization: UInt32, Sendable, CaseIterable {
    case none = 0
    case float16 = 1
    case int8 = 2
    case int4 = 3
}

public enum LogLevel: Int32, Sendable, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case fatal = 4
}

public enum DocumentOperation: Int32, Sendable, CaseIterable {
    case insert = 0
    case update = 1
    case upsert = 2
    case delete = 3
}

public struct SparseVector<Value>: Sendable, Equatable
where Value: BinaryFloatingPoint & Sendable & Equatable {
    public var indices: [UInt32]
    public var values: [Value]

    public init(indices: [UInt32], values: [Value]) throws(ZvecError) {
        guard indices.count == values.count else {
            throw .invalid("Sparse vector indices and values must have equal counts")
        }
        guard zip(indices, indices.dropFirst()).allSatisfy(<) else {
            throw .invalid("Sparse vector indices must be strictly increasing")
        }
        self.indices = indices
        self.values = values
    }
}

public struct PackedInt4Vector: Sendable, Equatable {
    public let bytes: Data
    public let dimensions: Int

    public init(bytes: Data, dimensions: Int) throws(ZvecError) {
        guard dimensions > 0 else { throw .invalid("Vector dimensions must be positive") }
        guard bytes.count == (dimensions + 1) / 2 else {
            throw .invalid("An Int4 vector requires ceil(dimensions / 2) bytes")
        }
        self.bytes = bytes
        self.dimensions = dimensions
    }
}

public enum ZvecValue: Sendable, Equatable {
    case null
    case binary(Data)
    case string(String)
    case bool(Bool)
    case int32(Int32)
    case int64(Int64)
    case uint32(UInt32)
    case uint64(UInt64)
    case float(Float)
    case double(Double)
    case vectorBinary32(Data)
    case vectorBinary64(Data)
    case vectorFloat16([Float16])
    case vectorFloat32([Float])
    case vectorFloat64([Double])
    case vectorInt4(PackedInt4Vector)
    case vectorInt8([Int8])
    case vectorInt16([Int16])
    case sparseVectorFloat16(SparseVector<Float16>)
    case sparseVectorFloat32(SparseVector<Float>)
    case arrayBinary([Data])
    case arrayString([String])
    case arrayBool([Bool])
    case arrayInt32([Int32])
    case arrayInt64([Int64])
    case arrayUInt32([UInt32])
    case arrayUInt64([UInt64])
    case arrayFloat([Float])
    case arrayDouble([Double])

    public var dataType: DataType? {
        switch self {
        case .null: nil
        case .binary: .binary
        case .string: .string
        case .bool: .bool
        case .int32: .int32
        case .int64: .int64
        case .uint32: .uint32
        case .uint64: .uint64
        case .float: .float
        case .double: .double
        case .vectorBinary32: .vectorBinary32
        case .vectorBinary64: .vectorBinary64
        case .vectorFloat16: .vectorFloat16
        case .vectorFloat32: .vectorFloat32
        case .vectorFloat64: .vectorFloat64
        case .vectorInt4: .vectorInt4
        case .vectorInt8: .vectorInt8
        case .vectorInt16: .vectorInt16
        case .sparseVectorFloat16: .sparseVectorFloat16
        case .sparseVectorFloat32: .sparseVectorFloat32
        case .arrayBinary: .arrayBinary
        case .arrayString: .arrayString
        case .arrayBool: .arrayBool
        case .arrayInt32: .arrayInt32
        case .arrayInt64: .arrayInt64
        case .arrayUInt32: .arrayUInt32
        case .arrayUInt64: .arrayUInt64
        case .arrayFloat: .arrayFloat
        case .arrayDouble: .arrayDouble
        }
    }
}

public enum DenseQueryVector: Sendable, Equatable {
    case binary(Data)
    case float16([Float16])
    case float32([Float])
    case float64([Double])
    case int4(PackedInt4Vector)
    case int8([Int8])
    case int16([Int16])
}
