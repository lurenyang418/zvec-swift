internal import CZvec
import Dispatch
import Foundation

public final class Collection: @unchecked Sendable {
    private let queue: DispatchQueue
    private var handle: OpaquePointer?
    private var cachedSchema: CollectionSchema

    private init(handle: OpaquePointer, schema: CollectionSchema) {
        self.handle = handle
        self.cachedSchema = schema
        self.queue = DispatchQueue(
            label: "dev.zvec.swift.collection.\(UUID().uuidString)",
            qos: .userInitiated,
            attributes: .concurrent
        )
    }

    public static func create(
        at url: URL,
        schema: CollectionSchema,
        options: CollectionOptions? = nil
    ) throws(ZvecError) -> Collection {
        try CAPI.typed {
            try ZvecRuntime.initialize()
            let nativeSchema = try NativeCollectionSchema(schema)
            let nativeOptions = try options.map(NativeCollectionOptions.init)
            var handle: OpaquePointer?
            try url.path.withCString {
                try CAPI.check(zvec_collection_create_and_open(
                    $0, nativeSchema.handle, nativeOptions?.handle, &handle
                ))
            }
            guard let handle else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
            return Collection(handle: handle, schema: schema)
        }
    }

    public static func open(
        at url: URL,
        options: CollectionOptions? = nil
    ) throws(ZvecError) -> Collection {
        try CAPI.typed {
            try ZvecRuntime.initialize()
            let nativeOptions = try options.map(NativeCollectionOptions.init)
            var handle: OpaquePointer?
            try url.path.withCString {
                try CAPI.check(zvec_collection_open($0, nativeOptions?.handle, &handle))
            }
            guard let handle else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
            do {
                let schema = try Self.readSchema(from: handle)
                return Collection(handle: handle, schema: schema)
            } catch {
                _ = zvec_collection_close(handle)
                throw error
            }
        }
    }

    public var schema: CollectionSchema {
        queue.sync { cachedSchema }
    }

    public func refreshSchema() throws(ZvecError) -> CollectionSchema {
        try write { handle in
            let schema = try Self.readSchema(from: handle)
            cachedSchema = schema
            return schema
        }
    }

    public func flush() throws(ZvecError) {
        try write { try CAPI.check(zvec_collection_flush($0)) }
    }

    public func optimize() throws(ZvecError) {
        try write { try CAPI.check(zvec_collection_optimize($0)) }
    }

    public func statistics() throws(ZvecError) -> CollectionStatistics {
        try read { handle in
            var native: OpaquePointer?
            try CAPI.check(zvec_collection_get_stats(handle, &native))
            guard let native else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
            defer { zvec_collection_stats_destroy(native) }
            let count = zvec_collection_stats_get_index_count(native)
            let indexes = (0..<count).map { index in
                IndexStatistics(
                    name: CAPI.string(zvec_collection_stats_get_index_name(native, index)) ?? "",
                    completeness: zvec_collection_stats_get_index_completeness(native, index)
                )
            }
            return CollectionStatistics(
                documentCount: zvec_collection_stats_get_doc_count(native),
                indexStatistics: indexes
            )
        }
    }

    @discardableResult
    public func insert(_ documents: [Document]) throws(ZvecError) -> WriteSummary {
        try writeDocuments(documents, operation: zvec_collection_insert)
    }

    @discardableResult
    public func update(_ documents: [Document]) throws(ZvecError) -> WriteSummary {
        try writeDocuments(documents, operation: zvec_collection_update)
    }

    @discardableResult
    public func upsert(_ documents: [Document]) throws(ZvecError) -> WriteSummary {
        try writeDocuments(documents, operation: zvec_collection_upsert)
    }

    public func insertWithResults(_ documents: [Document]) throws(ZvecError) -> [DocumentWriteResult] {
        try detailedWrite(documents, operation: zvec_collection_insert_with_results)
    }

    public func updateWithResults(_ documents: [Document]) throws(ZvecError) -> [DocumentWriteResult] {
        try detailedWrite(documents, operation: zvec_collection_update_with_results)
    }

    public func upsertWithResults(_ documents: [Document]) throws(ZvecError) -> [DocumentWriteResult] {
        try detailedWrite(documents, operation: zvec_collection_upsert_with_results)
    }

    @discardableResult
    public func delete(ids: [String]) throws(ZvecError) -> WriteSummary {
        try write { handle in
            guard !ids.isEmpty else { return WriteSummary(succeeded: 0, failed: 0) }
            var succeeded = 0
            var failed = 0
            try ids.withCStringArray { pointers in
                try CAPI.check(zvec_collection_delete(
                    handle, pointers, ids.count, &succeeded, &failed
                ))
            }
            return WriteSummary(succeeded: succeeded, failed: failed)
        }
    }

    public func deleteWithResults(ids: [String]) throws(ZvecError) -> [DocumentWriteResult] {
        try write { handle in
            guard !ids.isEmpty else { return [] }
            var results: UnsafeMutablePointer<zvec_write_result_t>?
            var count = 0
            try ids.withCStringArray { pointers in
                try CAPI.check(zvec_collection_delete_with_results(
                    handle, pointers, ids.count, &results, &count
                ))
            }
            defer { if let results { zvec_write_results_free(results, count) } }
            return Self.decodeWriteResults(ids: ids, native: results, count: count)
        }
    }

    public func delete(where filter: String) throws(ZvecError) {
        try write { handle in
            try filter.withCString { try CAPI.check(zvec_collection_delete_by_filter(handle, $0)) }
        }
    }

    public func fetch(
        ids: [String],
        outputFields: [String] = [],
        includeVector: Bool = false
    ) throws(ZvecError) -> [Document] {
        try read { handle in
            guard !ids.isEmpty else { return [] }
            let idCount = ids.count
            var documents: UnsafeMutablePointer<OpaquePointer?>?
            var count = 0
            try ids.withCStringArray { idPointers in
                try outputFields.withCStringArray { fields in
                    try CAPI.check(zvec_collection_fetch(
                        handle, idPointers, idCount,
                        fields, outputFields.count, includeVector, &documents, &count
                    ))
                }
            }
            return try Self.decodeDocuments(documents, count: count, schema: cachedSchema)
        }
    }

    public func query(_ query: VectorQuery) throws(ZvecError) -> [Document] {
        try read { handle in
            let native = try NativeVectorQuery(query)
            var documents: UnsafeMutablePointer<OpaquePointer?>?
            var count = 0
            try CAPI.check(zvec_collection_query(handle, native.handle, &documents, &count))
            return try Self.decodeDocuments(documents, count: count, schema: cachedSchema)
        }
    }

    public func query(_ query: MultiQuery) throws(ZvecError) -> [Document] {
        try read { handle in
            let native = try NativeMultiQuery(query)
            var documents: UnsafeMutablePointer<OpaquePointer?>?
            var count = 0
            try CAPI.check(zvec_collection_multi_query(handle, native.handle, &documents, &count))
            return try Self.decodeDocuments(documents, count: count, schema: cachedSchema)
        }
    }

    public func createIndex(_ index: IndexConfiguration, for field: String) throws(ZvecError) {
        try write { handle in
            let native = try NativeIndexConfiguration(index)
            try field.withCString {
                try CAPI.check(zvec_collection_create_index(handle, $0, native.handle))
            }
            _ = try refreshSchemaUnlocked(handle)
        }
    }

    public func dropIndex(for field: String) throws(ZvecError) {
        try write { handle in
            try field.withCString { try CAPI.check(zvec_collection_drop_index(handle, $0)) }
            _ = try refreshSchemaUnlocked(handle)
        }
    }

    public func addColumn(_ field: FieldSchema, defaultExpression: String? = nil) throws(ZvecError) {
        try write { handle in
            let native = try NativeFieldSchema(field)
            if let defaultExpression {
                try defaultExpression.withCString {
                    try CAPI.check(zvec_collection_add_column(handle, native.handle, $0))
                }
            } else {
                try CAPI.check(zvec_collection_add_column(handle, native.handle, nil))
            }
            _ = try refreshSchemaUnlocked(handle)
        }
    }

    public func dropColumn(_ name: String) throws(ZvecError) {
        try write { handle in
            try name.withCString { try CAPI.check(zvec_collection_drop_column(handle, $0)) }
            _ = try refreshSchemaUnlocked(handle)
        }
    }

    public func alterColumn(
        _ name: String,
        newName: String? = nil,
        schema: FieldSchema? = nil
    ) throws(ZvecError) {
        try write { handle in
            let native = try schema.map(NativeFieldSchema.init)
            try name.withCString { name in
                if let newName {
                    try newName.withCString {
                        try CAPI.check(zvec_collection_alter_column(handle, name, $0, native?.handle))
                    }
                } else {
                    try CAPI.check(zvec_collection_alter_column(handle, name, nil, native?.handle))
                }
            }
            _ = try refreshSchemaUnlocked(handle)
        }
    }

    /// Permanently deletes the collection data and closes this handle.
    public func destroy() throws(ZvecError) {
        try write { handle in
            try CAPI.check(zvec_collection_destroy(handle))
            try CAPI.check(zvec_collection_close(handle))
            self.handle = nil
        }
    }

    public func close() throws(ZvecError) {
        try writeAllowingClosed { handle in
            guard let handle else { return }
            try CAPI.check(zvec_collection_close(handle))
            self.handle = nil
        }
    }

    public func flush() async throws(ZvecError) { try await asyncWrite { try $0.flush() } }
    public func optimize() async throws(ZvecError) { try await asyncWrite { try $0.optimize() } }
    public func statistics() async throws(ZvecError) -> CollectionStatistics {
        try await asyncRead { try $0.statistics() }
    }
    public func insert(_ documents: [Document]) async throws(ZvecError) -> WriteSummary {
        try await asyncWrite { try $0.insert(documents) }
    }
    public func update(_ documents: [Document]) async throws(ZvecError) -> WriteSummary {
        try await asyncWrite { try $0.update(documents) }
    }
    public func upsert(_ documents: [Document]) async throws(ZvecError) -> WriteSummary {
        try await asyncWrite { try $0.upsert(documents) }
    }
    public func delete(ids: [String]) async throws(ZvecError) -> WriteSummary {
        try await asyncWrite { try $0.delete(ids: ids) }
    }
    public func fetch(
        ids: [String], outputFields: [String] = [], includeVector: Bool = false
    ) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.fetch(ids: ids, outputFields: outputFields, includeVector: includeVector) }
    }
    public func query(_ query: VectorQuery) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.query(query) }
    }
    public func query(_ query: MultiQuery) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.query(query) }
    }
    public func close() async throws(ZvecError) { try await asyncWrite { try $0.close() } }

    deinit {
        queue.sync(flags: .barrier) {
            if let handle {
                _ = zvec_collection_close(handle)
                self.handle = nil
            }
        }
    }

    private func writeDocuments(
        _ documents: [Document],
        operation: (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?, Int, UnsafeMutablePointer<Int>?, UnsafeMutablePointer<Int>?) -> zvec_error_code_t
    ) throws(ZvecError) -> WriteSummary {
        try write { handle in
            guard !documents.isEmpty else { return WriteSummary(succeeded: 0, failed: 0) }
            let native = try documents.map(NativeDocument.init)
            var handles = native.map { Optional($0.handle) }
            var succeeded = 0
            var failed = 0
            try handles.withUnsafeMutableBufferPointer {
                try CAPI.check(operation(handle, $0.baseAddress, $0.count, &succeeded, &failed))
            }
            return WriteSummary(succeeded: succeeded, failed: failed)
        }
    }

    private func detailedWrite(
        _ documents: [Document],
        operation: (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<zvec_write_result_t>?>?, UnsafeMutablePointer<Int>?) -> zvec_error_code_t
    ) throws(ZvecError) -> [DocumentWriteResult] {
        try write { handle in
            guard !documents.isEmpty else { return [] }
            let native = try documents.map(NativeDocument.init)
            var handles = native.map { Optional($0.handle) }
            var results: UnsafeMutablePointer<zvec_write_result_t>?
            var count = 0
            try handles.withUnsafeMutableBufferPointer {
                try CAPI.check(operation(handle, $0.baseAddress, $0.count, &results, &count))
            }
            defer { if let results { zvec_write_results_free(results, count) } }
            return Self.decodeWriteResults(ids: documents.map(\.id), native: results, count: count)
        }
    }

    private static func decodeWriteResults(
        ids: [String], native: UnsafePointer<zvec_write_result_t>?, count: Int
    ) -> [DocumentWriteResult] {
        guard let native else { return [] }
        return (0..<min(count, ids.count)).map { index in
            let result = native[index]
            let error = result.code == ZVEC_OK ? nil : ZvecError(
                code: CAPI.code(for: result.code),
                message: CAPI.string(result.message) ?? "Document write failed"
            )
            return DocumentWriteResult(id: ids[index], error: error)
        }
    }

    private static func decodeDocuments(
        _ documents: UnsafeMutablePointer<OpaquePointer?>?,
        count: Int,
        schema: CollectionSchema
    ) throws(ZvecError) -> [Document] {
        guard let documents else { return [] }
        // NativeDocument owns and destroys each document. Only the outer C
        // pointer array remains to be released here.
        defer { zvec_free(documents) }
        return try CAPI.typed {
            try (0..<count).compactMap { index in
                guard let handle = documents[index] else { return nil }
                return try NativeDocument(taking: handle).value(schema: schema)
            }
        }
    }

    private static func readSchema(from handle: OpaquePointer) throws(ZvecError) -> CollectionSchema {
        var native: OpaquePointer?
        try CAPI.check(zvec_collection_get_schema(handle, &native))
        guard let native else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
        return try CAPI.typed { try NativeCollectionSchema(taking: native).value() }
    }

    private func refreshSchemaUnlocked(_ handle: OpaquePointer) throws(ZvecError) -> CollectionSchema {
        let schema = try Self.readSchema(from: handle)
        cachedSchema = schema
        return schema
    }

    private func read<Result>(_ operation: (OpaquePointer) throws -> Result) throws(ZvecError) -> Result {
        let result: Swift.Result<Result, ZvecError> = queue.sync {
            guard let handle else {
                return .failure(ZvecError(code: .closed, message: "Collection is closed"))
            }
            do { return .success(try operation(handle)) }
            catch { return .failure(CAPI.coerce(error)) }
        }
        return try result.get()
    }

    private func write<Result>(_ operation: (OpaquePointer) throws -> Result) throws(ZvecError) -> Result {
        let result: Swift.Result<Result, ZvecError> = queue.sync(flags: .barrier) {
            guard let handle else {
                return .failure(ZvecError(code: .closed, message: "Collection is closed"))
            }
            do { return .success(try operation(handle)) }
            catch { return .failure(CAPI.coerce(error)) }
        }
        return try result.get()
    }

    private func writeAllowingClosed<Result>(
        _ operation: (OpaquePointer?) throws -> Result
    ) throws(ZvecError) -> Result {
        let result: Swift.Result<Result, ZvecError> = queue.sync(flags: .barrier) {
            do { return .success(try operation(handle)) }
            catch { return .failure(CAPI.coerce(error)) }
        }
        return try result.get()
    }

    private func asyncRead<Result: Sendable>(
        _ operation: @escaping @Sendable (Collection) throws -> Result
    ) async throws(ZvecError) -> Result {
        try await performAsync(operation)
    }

    private func asyncWrite<Result: Sendable>(
        _ operation: @escaping @Sendable (Collection) throws -> Result
    ) async throws(ZvecError) -> Result {
        try await performAsync(operation)
    }

    private func performAsync<Result: Sendable>(
        _ operation: @escaping @Sendable (Collection) throws -> Result
    ) async throws(ZvecError) -> Result {
        if Task.isCancelled { throw ZvecError(code: .cancelled, message: "Operation was cancelled") }
        let result: Swift.Result<Result, ZvecError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: .success(try operation(self))) }
                catch { continuation.resume(returning: .failure(CAPI.coerce(error))) }
            }
        }
        if Task.isCancelled { throw ZvecError(code: .cancelled, message: "Operation was cancelled") }
        return try result.get()
    }
}

private extension Array where Element == String {
    func withCStringArray<Result>(
        _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) throws -> Result
    ) throws -> Result {
        let storage: [UnsafeMutablePointer<CChar>?] = map { strdup($0) }
        defer { storage.forEach { if let pointer = $0 { free(pointer) } } }
        var pointers: [UnsafePointer<CChar>?] = storage.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        return try pointers.withUnsafeMutableBufferPointer {
            try body($0.baseAddress)
        }
    }
}
