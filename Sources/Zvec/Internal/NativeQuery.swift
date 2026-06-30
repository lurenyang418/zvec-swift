internal import CZvec
import Foundation

final class NativeVectorQuery {
    let handle: OpaquePointer

    init(_ query: VectorQuery) throws {
        guard let handle = zvec_vector_query_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            guard query.topK > 0 else { throw ZvecError.invalid("topK must be positive") }
            try CAPI.check(zvec_vector_query_set_topk(handle, CAPI.int32(query.topK, named: "topK")))
            try query.field.withCString {
                try CAPI.check(zvec_vector_query_set_field_name(handle, $0))
            }
            try query.vector.withUnsafeBytes {
                try CAPI.check(zvec_vector_query_set_query_vector(handle, $0.baseAddress, $0.count))
            }
            if let filter = query.filter {
                try filter.withCString { try CAPI.check(zvec_vector_query_set_filter(handle, $0)) }
            }
            try CAPI.check(zvec_vector_query_set_include_vector(handle, query.includeVector))
            try query.outputFields.withCStringArray {
                try CAPI.check(zvec_vector_query_set_output_fields(handle, $0, query.outputFields.count))
            }
            if let parameters = query.indexParameters {
                try NativeQueryParameters.attach(parameters, toVectorQuery: handle)
            }
        } catch {
            zvec_vector_query_destroy(handle)
            throw error
        }
    }

    deinit { zvec_vector_query_destroy(handle) }
}

final class NativeFullTextQuery {
    let handle: OpaquePointer

    init(_ query: FullTextQuery) throws {
        guard let handle = zvec_vector_query_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            guard query.topK > 0 else { throw ZvecError.invalid("topK must be positive") }
            try CAPI.check(zvec_vector_query_set_topk(handle, CAPI.int32(query.topK, named: "topK")))
            try query.field.withCString {
                try CAPI.check(zvec_vector_query_set_field_name(handle, $0))
            }
            let payload = try NativeFTS(query.query)
            try CAPI.check(zvec_vector_query_set_fts(handle, payload.handle))
            if let filter = query.filter {
                try filter.withCString { try CAPI.check(zvec_vector_query_set_filter(handle, $0)) }
            }
            try query.outputFields.withCStringArray {
                try CAPI.check(zvec_vector_query_set_output_fields(handle, $0, query.outputFields.count))
            }
            let operation = query.parameters.defaultOperator.rawValue.uppercased()
            guard let parameters = operation.withCString(zvec_query_params_fts_create) else {
                throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
            }
            let status = zvec_vector_query_set_fts_params(handle, parameters)
            if status != ZVEC_OK { zvec_query_params_fts_destroy(parameters) }
            try CAPI.check(status)
        } catch {
            zvec_vector_query_destroy(handle)
            throw error
        }
    }

    deinit { zvec_vector_query_destroy(handle) }
}

final class NativeGroupByQuery {
    let handle: OpaquePointer

    init(_ query: GroupByVectorQuery) throws {
        guard let handle = zvec_group_by_vector_query_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            let vector = query.vectorQuery
            guard vector.topK > 0 else { throw ZvecError.invalid("topK must be positive") }
            guard query.groupCount > 0 else { throw ZvecError.invalid("groupCount must be positive") }
            guard query.groupTopK > 0 else { throw ZvecError.invalid("groupTopK must be positive") }
            try vector.field.withCString {
                try CAPI.check(zvec_group_by_vector_query_set_field_name(handle, $0))
            }
            try query.groupByField.withCString {
                try CAPI.check(zvec_group_by_vector_query_set_group_by_field_name(handle, $0))
            }
            try CAPI.check(zvec_group_by_vector_query_set_group_count(handle, query.groupCount))
            try CAPI.check(zvec_group_by_vector_query_set_group_topk(handle, query.groupTopK))
            try vector.vector.withUnsafeBytes {
                try CAPI.check(zvec_group_by_vector_query_set_query_vector(handle, $0.baseAddress, $0.count))
            }
            if let filter = vector.filter {
                try filter.withCString {
                    try CAPI.check(zvec_group_by_vector_query_set_filter(handle, $0))
                }
            }
            try CAPI.check(zvec_group_by_vector_query_set_include_vector(handle, vector.includeVector))
            try vector.outputFields.withCStringArray {
                try CAPI.check(
                    zvec_group_by_vector_query_set_output_fields(
                        handle, $0, vector.outputFields.count
                    ))
            }
            if let parameters = vector.indexParameters {
                try NativeQueryParameters.attach(parameters, toGroupByQuery: handle)
            }
        } catch {
            zvec_group_by_vector_query_destroy(handle)
            throw error
        }
    }

    deinit { zvec_group_by_vector_query_destroy(handle) }
}

final class NativeFTS {
    let handle: OpaquePointer

    init(_ query: String) throws {
        guard let handle = zvec_fts_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            try query.withCString { try CAPI.check(zvec_fts_set_match_string(handle, $0)) }
        } catch {
            zvec_fts_destroy(handle)
            throw error
        }
    }

    deinit { zvec_fts_destroy(handle) }
}

final class NativeMultiQuery {
    let handle: OpaquePointer

    init(_ query: MultiQuery) throws {
        guard let handle = zvec_multi_query_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            guard query.queries.count >= 2 else {
                throw ZvecError.invalid("MultiQuery requires at least two subqueries")
            }
            guard query.topK > 0 else { throw ZvecError.invalid("topK must be positive") }
            try CAPI.check(zvec_multi_query_set_topk(handle, CAPI.int32(query.topK, named: "topK")))
            if let filter = query.filter {
                try filter.withCString { try CAPI.check(zvec_multi_query_set_filter(handle, $0)) }
            }
            try CAPI.check(zvec_multi_query_set_include_vector(handle, query.includeVector))
            try query.outputFields.withCStringArray {
                try CAPI.check(zvec_multi_query_set_output_fields(handle, $0, query.outputFields.count))
            }
            for subquery in query.queries {
                let native = try NativeSubQuery(subquery)
                try CAPI.check(zvec_multi_query_add_sub_query(handle, native.handle))
            }
            switch query.reranker {
            case let .reciprocalRankFusion(constant):
                try CAPI.check(
                    zvec_multi_query_set_rerank_rrf(
                        handle, CAPI.int32(constant, named: "rankConstant")
                    ))
            case let .weighted(weights):
                guard weights.count == query.queries.count else {
                    throw ZvecError.invalid("Weighted reranking requires one weight per subquery")
                }
                let doubles = weights.map(Double.init)
                try doubles.withUnsafeBufferPointer {
                    try CAPI.check(zvec_multi_query_set_rerank_weighted(handle, $0.baseAddress, $0.count))
                }
            }
        } catch {
            zvec_multi_query_destroy(handle)
            throw error
        }
    }

    deinit { zvec_multi_query_destroy(handle) }
}

final class NativeSubQuery {
    let handle: OpaquePointer

    init(_ query: SubQuery) throws {
        guard let handle = zvec_sub_query_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            guard query.topK > 0 else { throw ZvecError.invalid("Subquery candidate count must be positive") }
            try CAPI.check(
                zvec_sub_query_set_num_candidates(
                    handle, CAPI.int32(query.topK, named: "subquery topK")
                ))
            try query.field.withCString {
                try CAPI.check(zvec_sub_query_set_field_name(handle, $0))
            }
            switch query.payload {
            case let .dense(vector):
                try vector.withUnsafeBytes {
                    try CAPI.check(zvec_sub_query_set_query_vector(handle, $0.baseAddress, $0.count))
                }
            case let .sparseFloat32(vector):
                try vector.indices.withUnsafeBufferPointer { indices in
                    try vector.values.withUnsafeBufferPointer { values in
                        try CAPI.check(
                            zvec_sub_query_set_sparse_vector(
                                handle, indices.baseAddress, values.baseAddress, indices.count
                            ))
                    }
                }
            case let .fullText(text):
                let fts = try NativeFTS(text)
                try CAPI.check(zvec_sub_query_set_fts(handle, fts.handle))
                let op = (query.fullTextParameters ?? .init()).defaultOperator.rawValue.uppercased()
                guard let params = op.withCString(zvec_query_params_fts_create) else {
                    throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
                }
                let status = zvec_sub_query_set_fts_params(handle, params)
                if status != ZVEC_OK { zvec_query_params_fts_destroy(params) }
                try CAPI.check(status)
            }
            if let parameters = query.indexParameters {
                try NativeQueryParameters.attach(parameters, toSubQuery: handle)
            }
        } catch {
            zvec_sub_query_destroy(handle)
            throw error
        }
    }

    deinit { zvec_sub_query_destroy(handle) }
}

enum NativeQueryParameters {
    static func attach(_ value: IndexQueryParameters, toVectorQuery query: OpaquePointer) throws {
        switch value {
        case let .hnsw(value):
            let native = try makeHNSW(value)
            let status = zvec_vector_query_set_hnsw_params(query, native)
            if status != ZVEC_OK { zvec_query_params_hnsw_destroy(native) }
            try CAPI.check(status)
        case let .ivf(value):
            let native = try makeIVF(value)
            let status = zvec_vector_query_set_ivf_params(query, native)
            if status != ZVEC_OK { zvec_query_params_ivf_destroy(native) }
            try CAPI.check(status)
        case let .flat(value):
            let native = try makeFlat(value)
            let status = zvec_vector_query_set_flat_params(query, native)
            if status != ZVEC_OK { zvec_query_params_flat_destroy(native) }
            try CAPI.check(status)
        case .vamana:
            throw ZvecError(code: .notSupported, message: "Vamana/DiskANN is not supported on Apple platforms")
        }
    }

    static func attach(_ value: IndexQueryParameters, toSubQuery query: OpaquePointer) throws {
        switch value {
        case let .hnsw(value):
            let native = try makeHNSW(value)
            let status = zvec_sub_query_set_hnsw_params(query, native)
            if status != ZVEC_OK { zvec_query_params_hnsw_destroy(native) }
            try CAPI.check(status)
        case let .ivf(value):
            let native = try makeIVF(value)
            let status = zvec_sub_query_set_ivf_params(query, native)
            if status != ZVEC_OK { zvec_query_params_ivf_destroy(native) }
            try CAPI.check(status)
        case let .flat(value):
            let native = try makeFlat(value)
            let status = zvec_sub_query_set_flat_params(query, native)
            if status != ZVEC_OK { zvec_query_params_flat_destroy(native) }
            try CAPI.check(status)
        case .vamana:
            throw ZvecError(code: .notSupported, message: "Vamana/DiskANN is not supported on Apple platforms")
        }
    }

    static func attach(_ value: IndexQueryParameters, toGroupByQuery query: OpaquePointer) throws {
        switch value {
        case let .hnsw(value):
            let native = try makeHNSW(value)
            let status = zvec_group_by_vector_query_set_hnsw_params(query, native)
            if status != ZVEC_OK { zvec_query_params_hnsw_destroy(native) }
            try CAPI.check(status)
        case let .ivf(value):
            let native = try makeIVF(value)
            let status = zvec_group_by_vector_query_set_ivf_params(query, native)
            if status != ZVEC_OK { zvec_query_params_ivf_destroy(native) }
            try CAPI.check(status)
        case let .flat(value):
            let native = try makeFlat(value)
            let status = zvec_group_by_vector_query_set_flat_params(query, native)
            if status != ZVEC_OK { zvec_query_params_flat_destroy(native) }
            try CAPI.check(status)
        case .vamana:
            throw ZvecError(code: .notSupported, message: "Vamana/DiskANN is not supported on Apple platforms")
        }
    }

    private static func makeHNSW(_ value: HNSWQueryParameters) throws -> OpaquePointer {
        guard
            let native = zvec_query_params_hnsw_create(
                try CAPI.int32(value.efSearch, named: "efSearch"), value.radius ?? 0,
                value.linearSearch, value.useRefiner
            )
        else { throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT) }
        return native
    }

    private static func makeIVF(_ value: IVFQueryParameters) throws -> OpaquePointer {
        guard
            let native = zvec_query_params_ivf_create(
                try CAPI.int32(value.probeCount, named: "probeCount"), value.useRefiner,
                value.scaleFactor
            )
        else { throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT) }
        do {
            if let radius = value.radius {
                try CAPI.check(zvec_query_params_ivf_set_radius(native, radius))
            }
            try CAPI.check(zvec_query_params_ivf_set_is_linear(native, value.linearSearch))
            return native
        } catch {
            zvec_query_params_ivf_destroy(native)
            throw error
        }
    }

    private static func makeFlat(_ value: FlatQueryParameters) throws -> OpaquePointer {
        guard let native = zvec_query_params_flat_create(value.useRefiner, value.scaleFactor) else {
            throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT)
        }
        do {
            if let radius = value.radius {
                try CAPI.check(zvec_query_params_flat_set_radius(native, radius))
            }
            try CAPI.check(zvec_query_params_flat_set_is_linear(native, value.linearSearch))
            return native
        } catch {
            zvec_query_params_flat_destroy(native)
            throw error
        }
    }
}

extension DenseQueryVector {
    fileprivate func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) throws -> Result {
        switch self {
        case let .binary(data): try data.withUnsafeBytes(body)
        case let .float16(values): try values.withUnsafeBytes(body)
        case let .float32(values): try values.withUnsafeBytes(body)
        case let .float64(values): try values.withUnsafeBytes(body)
        case let .int4(value): try value.bytes.withUnsafeBytes(body)
        case let .int8(values): try values.withUnsafeBytes(body)
        case let .int16(values): try values.withUnsafeBytes(body)
        }
    }
}
