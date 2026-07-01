internal import CZvec
import Dispatch
import Foundation

public final class Collection: @unchecked Sendable {
    private let queue: DispatchQueue
    private var handle: OpaquePointer?
    private var cachedSchema: CollectionSchema
    public let location: URL

    private init(handle: OpaquePointer, schema: CollectionSchema, location: URL) {
        self.handle = handle
        self.cachedSchema = schema
        self.location = location.standardizedFileURL.resolvingSymlinksInPath()
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
                try CAPI.check(
                    zvec_collection_create_and_open(
                        $0, nativeSchema.handle, nativeOptions?.handle, &handle
                    ))
            }
            guard let handle else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
            return Collection(handle: handle, schema: schema, location: url)
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
                return Collection(handle: handle, schema: schema, location: url)
            } catch {
                _ = zvec_collection_close(handle)
                throw error
            }
        }
    }

    public static func create(
        at url: URL,
        schema: CollectionSchema,
        options: CollectionOptions? = nil
    ) async throws(ZvecError) -> Collection {
        try await runAsync { try create(at: url, schema: schema, options: options) }
    }

    public static func open(
        at url: URL,
        options: CollectionOptions? = nil
    ) async throws(ZvecError) -> Collection {
        try await runAsync { try open(at: url, options: options) }
    }

    public var schema: CollectionSchema {
        queue.sync { cachedSchema }
    }

    public var isClosed: Bool {
        queue.sync { handle == nil }
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

    public func options() throws(ZvecError) -> CollectionOptions {
        try read { handle in
            var native: OpaquePointer?
            try CAPI.check(zvec_collection_get_options(handle, &native))
            guard let native else { throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR) }
            defer { zvec_collection_options_destroy(native) }
            let maximumBufferSize = zvec_collection_options_get_max_buffer_size(native)
            return CollectionOptions(
                enableMemoryMapping: zvec_collection_options_get_enable_mmap(native),
                maximumBufferSize: maximumBufferSize == 0 ? nil : maximumBufferSize,
                readOnly: zvec_collection_options_get_read_only(native)
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
    public func insert(_ document: Document) throws(ZvecError) -> DocumentWriteResult {
        try Self.singleResult(try insertWithResults([document]), operation: "insert")
    }

    @discardableResult
    public func update(_ document: Document) throws(ZvecError) -> DocumentWriteResult {
        try Self.singleResult(try updateWithResults([document]), operation: "update")
    }

    @discardableResult
    public func upsert(_ document: Document) throws(ZvecError) -> DocumentWriteResult {
        try Self.singleResult(try upsertWithResults([document]), operation: "upsert")
    }

    @discardableResult
    public func delete(ids: [String]) throws(ZvecError) -> WriteSummary {
        try write { handle in
            guard !ids.isEmpty else { return WriteSummary(succeeded: 0, failed: 0) }
            var succeeded = 0
            var failed = 0
            try ids.withCStringArray { pointers in
                try CAPI.check(
                    zvec_collection_delete(
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
                try CAPI.check(
                    zvec_collection_delete_with_results(
                        handle, pointers, ids.count, &results, &count
                    ))
            }
            defer { if let results { zvec_write_results_free(results, count) } }
            return Self.decodeWriteResults(ids: ids, native: results, count: count)
        }
    }

    @discardableResult
    public func delete(id: String) throws(ZvecError) -> DocumentWriteResult {
        try Self.singleResult(try deleteWithResults(ids: [id]), operation: "delete")
    }

    public func delete(where filter: String) throws(ZvecError) {
        try write { handle in
            try filter.withCString { try CAPI.check(zvec_collection_delete_by_filter(handle, $0)) }
        }
    }

    public func fetch(
        ids: [String],
        outputFields: [String] = [],
        includeVector: Bool = true
    ) throws(ZvecError) -> [Document] {
        try read { handle in
            try fetchUnlocked(
                handle, ids: ids, outputFields: outputFields, includeVector: includeVector
            )
        }
    }

    public func fetch(
        id: String,
        outputFields: [String] = [],
        includeVector: Bool = true
    ) throws(ZvecError) -> Document? {
        try fetch(ids: [id], outputFields: outputFields, includeVector: includeVector).first
    }

    public func fetchResults(
        ids: [String],
        outputFields: [String] = [],
        includeVector: Bool = true
    ) throws(ZvecError) -> [DocumentFetchResult] {
        let documents = try fetch(
            ids: ids, outputFields: outputFields, includeVector: includeVector
        )
        let documentsByID = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.map { DocumentFetchResult(id: $0, document: documentsByID[$0]) }
    }

    public func browse(_ query: BrowseQuery = .init()) throws(ZvecError) -> BrowseResult {
        try read { handle in
            let native = try NativeBrowseQuery(query)
            let documents = try execute(native.handle, on: handle)
            return BrowseResult(
                documents: documents,
                limitReached: documents.count == query.limit
            )
        }
    }

    public func query(_ query: VectorQuery) throws(ZvecError) -> [Document] {
        try read { handle in
            let resolved = try resolveVectorSource(query, handle: handle)
            let native = try NativeVectorQuery(resolved)
            return try execute(native.handle, on: handle)
        }
    }

    public func query(_ query: FullTextQuery) throws(ZvecError) -> [Document] {
        try read { handle in
            let native = try NativeFullTextQuery(query)
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

    public func query(_ query: GroupByVectorQuery) throws(ZvecError) -> [GroupResult] {
        try read { handle in
            var resolved = query
            resolved.vectorQuery = try resolveVectorSource(query.vectorQuery, handle: handle)
            let native = try NativeGroupByQuery(resolved)
            var results: UnsafeMutablePointer<zvec_swift_group_result_t>?
            var count = 0
            try CAPI.check(
                zvec_swift_collection_group_by_query(
                    handle, native.handle, &results, &count
                ))
            guard let results else { return [] }
            defer { zvec_swift_group_results_free(results, count) }
            return try (0..<count).map { index in
                let result = results[index]
                let documents: [Document] = try (0..<result.document_count).compactMap { documentIndex -> Document? in
                    guard let handle = result.documents?[documentIndex] else { return nil }
                    // The shim owns these native documents until the result array is freed.
                    return try NativeDocument.borrowing(handle).value(schema: cachedSchema)
                }
                return GroupResult(
                    value: CAPI.string(result.group_value) ?? "",
                    documents: documents
                )
            }
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
    public func refreshSchema() async throws(ZvecError) -> CollectionSchema {
        try await asyncWrite { try $0.refreshSchema() }
    }
    public func statistics() async throws(ZvecError) -> CollectionStatistics {
        try await asyncRead { try $0.statistics() }
    }
    public func options() async throws(ZvecError) -> CollectionOptions {
        try await asyncRead { try $0.options() }
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
    public func insertWithResults(_ documents: [Document]) async throws(ZvecError) -> [DocumentWriteResult] {
        try await asyncWrite { try $0.insertWithResults(documents) }
    }
    public func updateWithResults(_ documents: [Document]) async throws(ZvecError) -> [DocumentWriteResult] {
        try await asyncWrite { try $0.updateWithResults(documents) }
    }
    public func upsertWithResults(_ documents: [Document]) async throws(ZvecError) -> [DocumentWriteResult] {
        try await asyncWrite { try $0.upsertWithResults(documents) }
    }
    @discardableResult
    public func insert(_ document: Document) async throws(ZvecError) -> DocumentWriteResult {
        try await asyncWrite { try $0.insert(document) }
    }
    @discardableResult
    public func update(_ document: Document) async throws(ZvecError) -> DocumentWriteResult {
        try await asyncWrite { try $0.update(document) }
    }
    @discardableResult
    public func upsert(_ document: Document) async throws(ZvecError) -> DocumentWriteResult {
        try await asyncWrite { try $0.upsert(document) }
    }
    public func delete(ids: [String]) async throws(ZvecError) -> WriteSummary {
        try await asyncWrite { try $0.delete(ids: ids) }
    }
    public func deleteWithResults(ids: [String]) async throws(ZvecError) -> [DocumentWriteResult] {
        try await asyncWrite { try $0.deleteWithResults(ids: ids) }
    }
    @discardableResult
    public func delete(id: String) async throws(ZvecError) -> DocumentWriteResult {
        try await asyncWrite { try $0.delete(id: id) }
    }
    public func delete(where filter: String) async throws(ZvecError) {
        try await asyncWrite { try $0.delete(where: filter) }
    }
    public func fetch(
        ids: [String], outputFields: [String] = [], includeVector: Bool = true
    ) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.fetch(ids: ids, outputFields: outputFields, includeVector: includeVector) }
    }
    public func fetch(
        id: String, outputFields: [String] = [], includeVector: Bool = true
    ) async throws(ZvecError) -> Document? {
        try await asyncRead {
            try $0.fetch(id: id, outputFields: outputFields, includeVector: includeVector)
        }
    }
    public func fetchResults(
        ids: [String], outputFields: [String] = [], includeVector: Bool = true
    ) async throws(ZvecError) -> [DocumentFetchResult] {
        try await asyncRead {
            try $0.fetchResults(
                ids: ids, outputFields: outputFields, includeVector: includeVector
            )
        }
    }
    public func browse(_ query: BrowseQuery = .init()) async throws(ZvecError) -> BrowseResult {
        try await asyncRead { try $0.browse(query) }
    }
    public func query(_ query: VectorQuery) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.query(query) }
    }
    public func query(_ query: FullTextQuery) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.query(query) }
    }
    public func query(_ query: MultiQuery) async throws(ZvecError) -> [Document] {
        try await asyncRead { try $0.query(query) }
    }
    public func query(_ query: GroupByVectorQuery) async throws(ZvecError) -> [GroupResult] {
        try await asyncRead { try $0.query(query) }
    }
    public func createIndex(_ index: IndexConfiguration, for field: String) async throws(ZvecError) {
        try await asyncWrite { try $0.createIndex(index, for: field) }
    }
    public func dropIndex(for field: String) async throws(ZvecError) {
        try await asyncWrite { try $0.dropIndex(for: field) }
    }
    public func addColumn(
        _ field: FieldSchema, defaultExpression: String? = nil
    ) async throws(ZvecError) {
        try await asyncWrite { try $0.addColumn(field, defaultExpression: defaultExpression) }
    }
    public func dropColumn(_ name: String) async throws(ZvecError) {
        try await asyncWrite { try $0.dropColumn(name) }
    }
    public func alterColumn(
        _ name: String, newName: String? = nil, schema: FieldSchema? = nil
    ) async throws(ZvecError) {
        try await asyncWrite { try $0.alterColumn(name, newName: newName, schema: schema) }
    }
    public func destroy() async throws(ZvecError) { try await asyncWrite { try $0.destroy() } }
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
        operation: (
            OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?, Int, UnsafeMutablePointer<Int>?,
            UnsafeMutablePointer<Int>?
        ) -> zvec_error_code_t
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
        operation: (
            OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?, Int,
            UnsafeMutablePointer<UnsafeMutablePointer<zvec_write_result_t>?>?, UnsafeMutablePointer<Int>?
        ) -> zvec_error_code_t
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
            let error =
                result.code == ZVEC_OK
                ? nil
                : ZvecError(
                    code: CAPI.code(for: result.code),
                    message: CAPI.string(result.message) ?? "Document write failed"
                )
            return DocumentWriteResult(id: ids[index], error: error)
        }
    }

    private static func singleResult(
        _ results: [DocumentWriteResult], operation: String
    ) throws(ZvecError) -> DocumentWriteResult {
        guard results.count == 1, let result = results.first else {
            throw ZvecError(
                code: .internalError,
                message: "Native \(operation) returned \(results.count) results for one document"
            )
        }
        return result
    }

    private func fetchUnlocked(
        _ handle: OpaquePointer,
        ids: [String],
        outputFields: [String],
        includeVector: Bool
    ) throws(ZvecError) -> [Document] {
        try CAPI.typed {
            guard !ids.isEmpty else { return [] }
            var documents: UnsafeMutablePointer<OpaquePointer?>?
            var count = 0
            try ids.withCStringArray { idPointers in
                try outputFields.withCStringArray { fields in
                    try CAPI.check(
                        zvec_collection_fetch(
                            handle, idPointers, ids.count,
                            fields, outputFields.count, includeVector, &documents, &count
                        ))
                }
            }
            return try Self.decodeDocuments(documents, count: count, schema: cachedSchema)
        }
    }

    private func execute(
        _ query: OpaquePointer, on handle: OpaquePointer
    ) throws(ZvecError) -> [Document] {
        var documents: UnsafeMutablePointer<OpaquePointer?>?
        var count = 0
        try CAPI.check(zvec_collection_query(handle, query, &documents, &count))
        return try Self.decodeDocuments(documents, count: count, schema: cachedSchema)
    }

    private func resolveVectorSource(
        _ query: VectorQuery, handle: OpaquePointer
    ) throws(ZvecError) -> VectorQuery {
        guard case let .documentID(id) = query.source else { return query }
        guard !id.isEmpty else { throw ZvecError.invalid("Document ID must not be empty") }
        guard let field = cachedSchema.field(named: query.field) else {
            throw ZvecError.invalid("Unknown vector field '\(query.field)'")
        }
        guard field.dataType.isDenseVector else {
            throw ZvecError(
                code: .notSupported,
                message: "Query by document ID currently requires a dense-vector field"
            )
        }
        let documents: [Document]
        do {
            documents = try fetchUnlocked(
                handle, ids: [id], outputFields: [query.field], includeVector: true
            )
        } catch let error {
            guard field.nullable else { throw error }
            throw ZvecError(
                code: .failedPrecondition,
                message:
                    "Unable to read vector field '\(query.field)' from document '\(id)': \(error.message)"
            )
        }
        guard let document = documents.first else {
            throw ZvecError(code: .notFound, message: "Document '\(id)' was not found")
        }
        guard let value = document.fields[query.field] else {
            throw ZvecError(
                code: .failedPrecondition,
                message: "Document '\(id)' has no value for vector field '\(query.field)'"
            )
        }
        var resolved = query
        resolved.source = .vector(try Self.queryVector(from: value, expected: field.dataType))
        return resolved
    }

    private static func queryVector(
        from value: ZvecValue, expected: DataType
    ) throws(ZvecError) -> DenseQueryVector {
        switch (expected, value) {
        case (.vectorBinary32, let .vectorBinary32(value)),
            (.vectorBinary64, let .vectorBinary64(value)):
            return .binary(value)
        case (.vectorFloat16, let .vectorFloat16(value)): return .float16(value)
        case (.vectorFloat32, let .vectorFloat32(value)): return .float32(value)
        case (.vectorFloat64, let .vectorFloat64(value)): return .float64(value)
        case (.vectorInt4, let .vectorInt4(value)): return .int4(value)
        case (.vectorInt8, let .vectorInt8(value)): return .int8(value)
        case (.vectorInt16, let .vectorInt16(value)): return .int16(value)
        default:
            throw ZvecError(
                code: .failedPrecondition,
                message: "Stored vector value does not match schema type \(expected)"
            )
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
            do { return .success(try operation(handle)) } catch { return .failure(CAPI.coerce(error)) }
        }
        return try result.get()
    }

    private func write<Result>(_ operation: (OpaquePointer) throws -> Result) throws(ZvecError) -> Result {
        let result: Swift.Result<Result, ZvecError> = queue.sync(flags: .barrier) {
            guard let handle else {
                return .failure(ZvecError(code: .closed, message: "Collection is closed"))
            }
            do { return .success(try operation(handle)) } catch { return .failure(CAPI.coerce(error)) }
        }
        return try result.get()
    }

    private func writeAllowingClosed<Result>(
        _ operation: (OpaquePointer?) throws -> Result
    ) throws(ZvecError) -> Result {
        let result: Swift.Result<Result, ZvecError> = queue.sync(flags: .barrier) {
            do { return .success(try operation(handle)) } catch { return .failure(CAPI.coerce(error)) }
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
                do { continuation.resume(returning: .success(try operation(self))) } catch {
                    continuation.resume(returning: .failure(CAPI.coerce(error)))
                }
            }
        }
        if Task.isCancelled { throw ZvecError(code: .cancelled, message: "Operation was cancelled") }
        return try result.get()
    }

    private static func runAsync<Result: Sendable>(
        _ operation: @escaping @Sendable () throws -> Result
    ) async throws(ZvecError) -> Result {
        if Task.isCancelled {
            throw ZvecError(code: .cancelled, message: "Operation was cancelled")
        }
        let result: Swift.Result<Result, ZvecError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: .success(try operation())) } catch {
                    continuation.resume(returning: .failure(CAPI.coerce(error)))
                }
            }
        }
        if Task.isCancelled {
            throw ZvecError(code: .cancelled, message: "Operation was cancelled")
        }
        return try result.get()
    }
}
