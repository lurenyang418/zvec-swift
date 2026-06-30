internal import CZvec
import Foundation

final class NativeDocument {
    let handle: OpaquePointer

    init(_ document: Document) throws {
        guard let handle = zvec_doc_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            document.id.withCString { zvec_doc_set_pk(handle, $0) }
            if let documentID = document.documentID { zvec_doc_set_doc_id(handle, documentID) }
            if let score = document.score { zvec_doc_set_score(handle, score) }
            zvec_doc_set_operator(handle, zvec_doc_operator_t(rawValue: UInt32(document.operation.rawValue)))
            for (name, value) in document.fields {
                try Self.add(value, named: name, to: handle)
            }
        } catch {
            zvec_doc_destroy(handle)
            throw error
        }
    }

    init(taking handle: OpaquePointer) {
        self.handle = handle
    }

    func value(schema: CollectionSchema) throws -> Document {
        let id = CAPI.string(zvec_doc_get_pk_pointer(handle)) ?? ""
        var fields: [String: ZvecValue] = [:]
        fields.reserveCapacity(schema.fields.count)
        for field in schema.fields where zvec_doc_has_field(handle, field.name) {
            if zvec_doc_is_field_null(handle, field.name) {
                fields[field.name] = .null
            } else if zvec_doc_has_field_value(handle, field.name) {
                fields[field.name] = try Self.read(field, from: handle)
            }
        }
        return Document(
            id: id,
            fields: fields,
            operation: DocumentOperation(rawValue: Int32(zvec_doc_get_operator(handle).rawValue)) ?? .insert,
            documentID: zvec_doc_get_doc_id(handle),
            score: zvec_doc_get_score(handle)
        )
    }

    private static func add(
        _ value: ZvecValue,
        named name: String,
        to document: OpaquePointer
    ) throws {
        if case .null = value {
            try name.withCString { try CAPI.check(zvec_doc_set_field_null(document, $0)) }
            return
        }
        guard let type = value.dataType else { return }

        switch value {
        case let .string(string):
            try addData(Data(string.utf8), type: type, named: name, to: document)
        case let .binary(data), let .vectorBinary32(data), let .vectorBinary64(data):
            try addData(data, type: type, named: name, to: document)
        case let .bool(value): try addScalar(value, type: type, named: name, to: document)
        case let .int32(value): try addScalar(value, type: type, named: name, to: document)
        case let .int64(value): try addScalar(value, type: type, named: name, to: document)
        case let .uint32(value): try addScalar(value, type: type, named: name, to: document)
        case let .uint64(value): try addScalar(value, type: type, named: name, to: document)
        case let .float(value): try addScalar(value, type: type, named: name, to: document)
        case let .double(value): try addScalar(value, type: type, named: name, to: document)
        case let .vectorFloat16(values): try addArray(values, type: type, named: name, to: document)
        case let .vectorFloat32(values): try addArray(values, type: type, named: name, to: document)
        case let .vectorFloat64(values): try addArray(values, type: type, named: name, to: document)
        case let .vectorInt4(values): try addData(values.bytes, type: type, named: name, to: document)
        case let .vectorInt8(values): try addArray(values, type: type, named: name, to: document)
        case let .vectorInt16(values): try addArray(values, type: type, named: name, to: document)
        case let .sparseVectorFloat16(values):
            try addSparse(values, type: type, named: name, to: document)
        case let .sparseVectorFloat32(values):
            try addSparse(values, type: type, named: name, to: document)
        case let .arrayBinary(values):
            var data = Data()
            for value in values {
                var count = UInt32(value.count).littleEndian
                withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
                data.append(value)
            }
            try addData(data, type: type, named: name, to: document)
        case let .arrayString(values):
            let nativeStrings = values.map { value in value.withCString(zvec_string_create) }
            defer { nativeStrings.forEach { if let value = $0 { zvec_free_string(value) } } }
            try nativeStrings.withUnsafeBufferPointer { buffer in
                try name.withCString {
                    try CAPI.check(zvec_doc_add_field_by_value(
                        document,
                        $0,
                        type.rawValue,
                        buffer.baseAddress,
                        buffer.count * MemoryLayout<UnsafeMutablePointer<zvec_string_t>?>.stride
                    ))
                }
            }
        case let .arrayBool(values):
            try addArray(values.map { $0 ? UInt8(1) : UInt8(0) }, type: type, named: name, to: document)
        case let .arrayInt32(values): try addArray(values, type: type, named: name, to: document)
        case let .arrayInt64(values): try addArray(values, type: type, named: name, to: document)
        case let .arrayUInt32(values): try addArray(values, type: type, named: name, to: document)
        case let .arrayUInt64(values): try addArray(values, type: type, named: name, to: document)
        case let .arrayFloat(values): try addArray(values, type: type, named: name, to: document)
        case let .arrayDouble(values): try addArray(values, type: type, named: name, to: document)
        case .null: break
        }
    }

    private static func addScalar<Value>(
        _ value: Value,
        type: DataType,
        named name: String,
        to document: OpaquePointer
    ) throws {
        var value = value
        try withUnsafeBytes(of: &value) { bytes in
            try addBytes(bytes, type: type, named: name, to: document)
        }
    }

    private static func addArray<Value>(
        _ values: [Value],
        type: DataType,
        named name: String,
        to document: OpaquePointer
    ) throws {
        try values.withUnsafeBytes { try addBytes($0, type: type, named: name, to: document) }
    }

    private static func addSparse<Value>(
        _ vector: SparseVector<Value>,
        type: DataType,
        named name: String,
        to document: OpaquePointer
    ) throws where Value: BinaryFloatingPoint & Sendable & Equatable {
        var data = Data()
        var count = UInt(vector.indices.count)
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        vector.indices.withUnsafeBytes { data.append(contentsOf: $0) }
        vector.values.withUnsafeBytes { data.append(contentsOf: $0) }
        try addData(data, type: type, named: name, to: document)
    }

    private static func addData(
        _ data: Data,
        type: DataType,
        named name: String,
        to document: OpaquePointer
    ) throws {
        try data.withUnsafeBytes { try addBytes($0, type: type, named: name, to: document) }
    }

    private static func addBytes(
        _ bytes: UnsafeRawBufferPointer,
        type: DataType,
        named name: String,
        to document: OpaquePointer
    ) throws {
        try name.withCString { name in
            if let pointer = bytes.baseAddress {
                try CAPI.check(zvec_doc_add_field_by_value(
                    document, name, type.rawValue, pointer, bytes.count
                ))
            } else {
                var empty: UInt8 = 0
                try withUnsafePointer(to: &empty) { pointer in
                    try CAPI.check(zvec_doc_add_field_by_value(
                        document, name, type.rawValue, pointer, 0
                    ))
                }
            }
        }
    }

    private static func read(_ field: FieldSchema, from document: OpaquePointer) throws -> ZvecValue {
        let data = try copyValue(field.name, type: field.dataType, from: document)
        switch field.dataType {
        case .binary: return .binary(data)
        case .string: return .string(String(decoding: data, as: UTF8.self))
        case .bool: return .bool(data.load(as: Bool.self))
        case .int32: return .int32(data.load(as: Int32.self))
        case .int64: return .int64(data.load(as: Int64.self))
        case .uint32: return .uint32(data.load(as: UInt32.self))
        case .uint64: return .uint64(data.load(as: UInt64.self))
        case .float: return .float(data.load(as: Float.self))
        case .double: return .double(data.load(as: Double.self))
        case .vectorBinary32: return .vectorBinary32(data)
        case .vectorBinary64: return .vectorBinary64(data)
        case .vectorFloat16: return .vectorFloat16(data.array(of: Float16.self))
        case .vectorFloat32: return .vectorFloat32(data.array(of: Float.self))
        case .vectorFloat64: return .vectorFloat64(data.array(of: Double.self))
        case .vectorInt4:
            return .vectorInt4(try PackedInt4Vector(bytes: data, dimensions: field.dimensions))
        case .vectorInt8: return .vectorInt8(data.array(of: Int8.self))
        case .vectorInt16: return .vectorInt16(data.array(of: Int16.self))
        case .sparseVectorFloat16:
            let pair: (indices: [UInt32], values: [Float16]) = try data.sparse()
            return .sparseVectorFloat16(try SparseVector(indices: pair.indices, values: pair.values))
        case .sparseVectorFloat32:
            let pair: (indices: [UInt32], values: [Float]) = try data.sparse()
            return .sparseVectorFloat32(try SparseVector(indices: pair.indices, values: pair.values))
        case .arrayBinary:
            // Upstream v0.5.1 flattens binary array elements when reading.
            return .arrayBinary([data])
        case .arrayString:
            let values = data.split(separator: 0, omittingEmptySubsequences: false)
            return .arrayString(values.dropLast().map { String(decoding: $0, as: UTF8.self) })
        case .arrayBool:
            return .arrayBool(data.flatMap { byte in (0..<8).map { byte & (1 << $0) != 0 } })
        case .arrayInt32: return .arrayInt32(data.array(of: Int32.self))
        case .arrayInt64: return .arrayInt64(data.array(of: Int64.self))
        case .arrayUInt32: return .arrayUInt32(data.array(of: UInt32.self))
        case .arrayUInt64: return .arrayUInt64(data.array(of: UInt64.self))
        case .arrayFloat: return .arrayFloat(data.array(of: Float.self))
        case .arrayDouble: return .arrayDouble(data.array(of: Double.self))
        case .undefined: throw ZvecError.invalid("Cannot decode an undefined field type")
        }
    }

    private static func copyValue(
        _ name: String, type: DataType, from document: OpaquePointer
    ) throws -> Data {
        var pointer: UnsafeMutableRawPointer?
        var count = 0
        try name.withCString {
            try CAPI.check(zvec_doc_get_field_value_copy(
                document, $0, type.rawValue, &pointer, &count
            ))
        }
        guard let pointer else { return Data() }
        defer { zvec_free(pointer) }
        return Data(bytes: pointer, count: count)
    }

    deinit { zvec_doc_destroy(handle) }
}

private extension Data {
    func load<Value>(as type: Value.Type) -> Value {
        withUnsafeBytes { bytes in
            precondition(bytes.count >= MemoryLayout<Value>.size)
            return bytes.loadUnaligned(as: Value.self)
        }
    }

    func array<Value>(of type: Value.Type) -> [Value] {
        guard !isEmpty else { return [] }
        return withUnsafeBytes { bytes in
            let count = bytes.count / MemoryLayout<Value>.stride
            return (0..<count).map { bytes.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Value>.stride, as: Value.self) }
        }
    }

    func sparse<Value>() throws -> (indices: [UInt32], values: [Value]) {
        let count = Int(load(as: UInt.self))
        let indexOffset = MemoryLayout<UInt>.size
        let valueOffset = indexOffset + count * MemoryLayout<UInt32>.stride
        let required = valueOffset + count * MemoryLayout<Value>.stride
        guard self.count >= required else { throw ZvecError.invalid("Malformed sparse vector returned by CZvec") }
        return withUnsafeBytes { bytes in
            let indices = (0..<count).map {
                bytes.loadUnaligned(fromByteOffset: indexOffset + $0 * MemoryLayout<UInt32>.stride, as: UInt32.self)
            }
            let values = (0..<count).map {
                bytes.loadUnaligned(fromByteOffset: valueOffset + $0 * MemoryLayout<Value>.stride, as: Value.self)
            }
            return (indices, values)
        }
    }
}
