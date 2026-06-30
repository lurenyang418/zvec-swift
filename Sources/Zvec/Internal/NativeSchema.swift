internal import CZvec
import Foundation

final class NativeCollectionSchema {
    let handle: OpaquePointer

    init(_ schema: CollectionSchema) throws {
        guard let handle = schema.name.withCString(zvec_collection_schema_create) else {
            throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
        }
        self.handle = handle
        do {
            try CAPI.check(
                zvec_collection_schema_set_max_doc_count_per_segment(
                    handle, schema.maximumDocumentsPerSegment
                ))
            for field in schema.fields {
                let nativeField = try NativeFieldSchema(field)
                try CAPI.check(zvec_collection_schema_add_field(handle, nativeField.handle))
            }
            var validationMessage: UnsafeMutablePointer<zvec_string_t>?
            let status = zvec_collection_schema_validate(handle, &validationMessage)
            if let validationMessage { zvec_free_string(validationMessage) }
            try CAPI.check(status)
        } catch {
            zvec_collection_schema_destroy(handle)
            throw error
        }
    }

    init(taking handle: OpaquePointer) {
        self.handle = handle
    }

    func value() throws -> CollectionSchema {
        let name = CAPI.string(zvec_collection_schema_get_name(handle)) ?? ""
        var names: UnsafeMutablePointer<UnsafePointer<CChar>?>?
        var count = 0
        try CAPI.check(zvec_collection_schema_get_all_field_names(handle, &names, &count))
        defer { if let names { zvec_free(names) } }

        var fields: [FieldSchema] = []
        fields.reserveCapacity(count)
        for index in 0..<count {
            guard let fieldName = names?[index],
                let native = zvec_collection_schema_get_field(handle, fieldName)
            else { continue }
            fields.append(try NativeFieldSchema.decode(native))
        }
        return try CollectionSchema(
            name: name,
            fields: fields,
            maximumDocumentsPerSegment: zvec_collection_schema_get_max_doc_count_per_segment(handle)
        )
    }

    deinit { zvec_collection_schema_destroy(handle) }
}

final class NativeFieldSchema {
    let handle: OpaquePointer

    init(_ field: FieldSchema) throws {
        guard
            let handle = field.name.withCString({
                zvec_field_schema_create($0, field.dataType.rawValue, field.nullable, UInt32(field.dimensions))
            })
        else {
            throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
        }
        self.handle = handle
        do {
            if let index = field.index {
                let nativeIndex = try NativeIndexConfiguration(index)
                try CAPI.check(zvec_field_schema_set_index_params(handle, nativeIndex.handle))
            }
        } catch {
            zvec_field_schema_destroy(handle)
            throw error
        }
    }

    static func decode(_ handle: OpaquePointer) throws -> FieldSchema {
        let name = CAPI.string(zvec_field_schema_get_name(handle)) ?? ""
        guard let type = DataType(rawValue: zvec_field_schema_get_data_type(handle)) else {
            throw ZvecError.invalid("Native schema contains an unknown data type")
        }
        let index = try zvec_field_schema_get_index_params(handle).map(NativeIndexConfiguration.decode)
        return try FieldSchema(
            name,
            type: type,
            nullable: zvec_field_schema_is_nullable(handle),
            dimensions: Int(zvec_field_schema_get_dimension(handle)),
            index: index
        )
    }

    deinit { zvec_field_schema_destroy(handle) }
}

final class NativeIndexConfiguration {
    let handle: OpaquePointer

    init(_ configuration: IndexConfiguration) throws {
        let indexType: UInt32
        switch configuration {
        case .hnsw: indexType = UInt32(ZVEC_INDEX_TYPE_HNSW)
        case .ivf: indexType = UInt32(ZVEC_INDEX_TYPE_IVF)
        case .flat: indexType = UInt32(ZVEC_INDEX_TYPE_FLAT)
        case .vamana: indexType = UInt32(ZVEC_INDEX_TYPE_VAMANA)
        case .inverted: indexType = UInt32(ZVEC_INDEX_TYPE_INVERT)
        case .fullText: indexType = UInt32(ZVEC_INDEX_TYPE_FTS)
        }
        guard let handle = zvec_index_params_create(indexType) else {
            throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
        }
        self.handle = handle
        do {
            switch configuration {
            case let .hnsw(metric, quantization, m, efConstruction):
                try setVector(metric: metric, quantization: quantization)
                try CAPI.check(zvec_index_params_set_hnsw_params(handle, Int32(m), Int32(efConstruction)))
            case let .ivf(metric, quantization, listCount, iterations, useSOAR):
                try setVector(metric: metric, quantization: quantization)
                try CAPI.check(
                    zvec_index_params_set_ivf_params(
                        handle, Int32(listCount), Int32(iterations), useSOAR
                    ))
            case let .flat(metric, quantization):
                try setVector(metric: metric, quantization: quantization)
            case let .vamana(metric, maxDegree, buildListSize, alpha):
                #if os(macOS) || os(iOS)
                    throw ZvecError(code: .notSupported, message: "Vamana/DiskANN is not supported on Apple platforms")
                #else
                    try setVector(metric: metric, quantization: .none)
                    try CAPI.check(
                        zvec_index_params_set_vamana_params(
                            handle, Int32(maxDegree), Int32(buildListSize), alpha, false, false
                        ))
                #endif
            case let .inverted(range, wildcard):
                try CAPI.check(zvec_index_params_set_invert_params(handle, range, wildcard))
            case let .fullText(tokenizer, filters, options):
                let nativeFilters = NativeStringArray(filters)
                let extra = try Self.jsonString(options)
                try tokenizer.nativeName.withCString { tokenizerName in
                    try extra.withCString { extra in
                        try CAPI.check(
                            zvec_index_params_set_fts_params(
                                handle, tokenizerName, nativeFilters?.handle, extra
                            ))
                    }
                }
            }
        } catch {
            zvec_index_params_destroy(handle)
            throw error
        }
    }

    private func setVector(metric: Metric, quantization: Quantization) throws {
        try CAPI.check(zvec_index_params_set_metric_type(handle, metric.rawValue))
        try CAPI.check(zvec_index_params_set_quantize_type(handle, quantization.rawValue))
    }

    static func decode(_ handle: OpaquePointer) throws -> IndexConfiguration {
        let metric = Metric(rawValue: zvec_index_params_get_metric_type(handle)) ?? .undefined
        let quantization = Quantization(rawValue: zvec_index_params_get_quantize_type(handle)) ?? .none
        switch zvec_index_params_get_type(handle) {
        case UInt32(ZVEC_INDEX_TYPE_HNSW):
            return .hnsw(
                metric: metric,
                quantization: quantization,
                m: Int(zvec_index_params_get_hnsw_m(handle)),
                efConstruction: Int(zvec_index_params_get_hnsw_ef_construction(handle))
            )
        case UInt32(ZVEC_INDEX_TYPE_IVF):
            var lists: Int32 = 0
            var iterations: Int32 = 0
            var soar = false
            try CAPI.check(zvec_index_params_get_ivf_params(handle, &lists, &iterations, &soar))
            return .ivf(
                metric: metric,
                quantization: quantization,
                listCount: Int(lists),
                iterations: Int(iterations),
                useSOAR: soar
            )
        case UInt32(ZVEC_INDEX_TYPE_FLAT):
            return .flat(metric: metric, quantization: quantization)
        case UInt32(ZVEC_INDEX_TYPE_VAMANA):
            var degree: Int32 = 0
            var listSize: Int32 = 0
            var alpha: Float = 0
            var saturate = false
            var contiguous = false
            try CAPI.check(
                zvec_index_params_get_vamana_params(
                    handle, &degree, &listSize, &alpha, &saturate, &contiguous
                ))
            return .vamana(
                metric: metric, maxDegree: Int(degree), buildListSize: Int(listSize), alpha: alpha
            )
        case UInt32(ZVEC_INDEX_TYPE_INVERT):
            var range = false
            var wildcard = false
            try CAPI.check(zvec_index_params_get_invert_params(handle, &range, &wildcard))
            return .inverted(enableRangeOptimization: range, enableWildcard: wildcard)
        case UInt32(ZVEC_INDEX_TYPE_FTS):
            var tokenizer: UnsafePointer<CChar>?
            var filters: UnsafeMutablePointer<zvec_string_array_t>?
            var extra: UnsafePointer<CChar>?
            try CAPI.check(zvec_index_params_get_fts_params(handle, &tokenizer, &filters, &extra))
            defer { if let filters { zvec_string_array_destroy(filters) } }
            let tokenizerValue: FullTextTokenizer =
                switch CAPI.string(tokenizer) {
                case "whitespace": .whitespace
                case "jieba": .jieba
                default: .standard
                }
            let filterValues = NativeStringArray.values(filters)
            let options = Self.decodeJSON(CAPI.string(extra))
            return .fullText(tokenizer: tokenizerValue, tokenFilters: filterValues, options: options)
        default:
            throw ZvecError.invalid("Native schema contains an unknown index type")
        }
    }

    private static func jsonString(_ options: [String: String]) throws -> String {
        guard !options.isEmpty else { return "{}" }
        do {
            let data = try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw ZvecError.invalid("Invalid full-text index options")
        }
    }

    private static func decodeJSON(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8),
            let result = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return result
    }

    deinit { zvec_index_params_destroy(handle) }
}

final class NativeStringArray {
    let handle: UnsafeMutablePointer<zvec_string_array_t>

    init?(_ values: [String]) {
        guard let handle = zvec_string_array_create(values.count) else { return nil }
        self.handle = handle
        for (index, value) in values.enumerated() {
            value.withCString { zvec_string_array_add(handle, index, $0) }
        }
    }

    static func values(_ array: UnsafePointer<zvec_string_array_t>?) -> [String] {
        guard let array else { return [] }
        return (0..<array.pointee.count).map { index in
            let value = array.pointee.strings[index]
            guard let data = value.data else { return "" }
            return String(decoding: Data(bytes: data, count: value.length), as: UTF8.self)
        }
    }

    deinit { zvec_string_array_destroy(handle) }
}

final class NativeCollectionOptions {
    let handle: OpaquePointer

    init(_ options: CollectionOptions?) throws {
        guard let handle = zvec_collection_options_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        guard let options else { return }
        do {
            try CAPI.check(zvec_collection_options_set_enable_mmap(handle, options.enableMemoryMapping))
            if let size = options.maximumBufferSize {
                guard size >= 0 else { throw ZvecError.invalid("Maximum buffer size must not be negative") }
                try CAPI.check(zvec_collection_options_set_max_buffer_size(handle, size))
            }
            try CAPI.check(zvec_collection_options_set_read_only(handle, options.readOnly))
        } catch {
            zvec_collection_options_destroy(handle)
            throw error
        }
    }

    deinit { zvec_collection_options_destroy(handle) }
}
