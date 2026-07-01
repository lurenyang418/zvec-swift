internal import CZvec
import Foundation
import os

public struct ZvecVersion: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ZvecVersion, rhs: ZvecVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public enum ZvecRuntime {
    private struct State: Sendable {
        var initialized = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let queue = DispatchQueue(label: "dev.zvec.swift.runtime", qos: .userInitiated)

    public static var version: String {
        CAPI.string(zvec_get_version()) ?? "unknown"
    }

    public static var nativeVersion: ZvecVersion {
        ZvecVersion(
            major: Int(zvec_get_version_major()),
            minor: Int(zvec_get_version_minor()),
            patch: Int(zvec_get_version_patch())
        )
    }

    public static var isInitialized: Bool {
        state.withLock { $0.initialized || zvec_is_initialized() }
    }

    public static var capabilities: ZvecCapabilities { ZvecCapabilities() }

    public static func initialize(configuration: Configuration? = nil) throws(ZvecError) {
        try CAPI.typed {
            try state.withLock { state in
                if state.initialized || zvec_is_initialized() {
                    state.initialized = true
                    return
                }
                guard
                    zvec_check_version(
                        Int32(CAPI.minimumVersion.major),
                        Int32(CAPI.minimumVersion.minor),
                        Int32(CAPI.minimumVersion.patch)
                    )
                else {
                    throw ZvecError(
                        code: .incompatibleNativeVersion(required: "0.5.1", actual: version),
                        message: "CZvec 0.5.1 or newer is required"
                    )
                }

                registerBundledJiebaDictionaryIfPresent()
                let native = try NativeConfiguration(configuration)
                try native.withHandle { try CAPI.check(zvec_initialize($0)) }
                state.initialized = true
            }
        }
    }

    public static func initialize(configuration: Configuration? = nil) async throws(ZvecError) {
        try await performAsync { try initialize(configuration: configuration) }
    }

    public static func shutdown() throws(ZvecError) {
        try CAPI.typed {
            try state.withLock { state in
                guard state.initialized || zvec_is_initialized() else { return }
                try CAPI.check(zvec_shutdown())
                state.initialized = false
            }
        }
    }

    public static func shutdown() async throws(ZvecError) {
        try await performAsync { try shutdown() }
    }

    private static func performAsync(
        _ operation: @escaping @Sendable () throws -> Void
    ) async throws(ZvecError) {
        if Task.isCancelled {
            throw ZvecError(code: .cancelled, message: "Operation was cancelled")
        }
        let result: Result<Void, ZvecError> = await withCheckedContinuation { continuation in
            queue.async {
                do {
                    try operation()
                    continuation.resume(returning: .success(()))
                } catch {
                    continuation.resume(returning: .failure(CAPI.coerce(error)))
                }
            }
        }
        if Task.isCancelled {
            throw ZvecError(code: .cancelled, message: "Operation was cancelled")
        }
        try result.get()
    }

    private static func registerBundledJiebaDictionaryIfPresent() {
        // A signed macOS app may only seal resources below Contents. Prefer the
        // standard app Resources location; retain Bundle.module for SwiftPM CLI
        // builds and tests.
        let resourceBundle: Bundle
        if let resources = Bundle.main.resourceURL,
            let bundled = Bundle(
                url: resources.appending(path: "zvec-swift_Zvec.bundle", directoryHint: .isDirectory)
            )
        {
            resourceBundle = bundled
        } else {
            resourceBundle = Bundle.module
        }
        guard let directory = resourceBundle.url(forResource: "jieba_dict", withExtension: nil),
            FileManager.default.fileExists(atPath: directory.appending(path: "jieba.dict.utf8").path),
            FileManager.default.fileExists(atPath: directory.appending(path: "hmm_model.utf8").path)
        else { return }
        directory.path.withCString(zvec_set_default_jieba_dict_dir)
    }
}

private struct NativeConfiguration: ~Copyable {
    private var handle: OpaquePointer?

    init(_ configuration: Configuration?) throws {
        guard let configuration else {
            handle = nil
            return
        }
        try configuration.validate()
        guard let handle = zvec_config_data_create() else {
            throw CAPI.error(for: ZVEC_ERROR_INTERNAL_ERROR)
        }
        self.handle = handle
        do {
            if let value = configuration.memoryLimitBytes {
                try CAPI.check(zvec_config_data_set_memory_limit(handle, value))
            }
            if let value = configuration.queryThreadCount {
                try CAPI.check(zvec_config_data_set_query_thread_count(handle, value))
            }
            if let value = configuration.optimizeThreadCount {
                try CAPI.check(zvec_config_data_set_optimize_thread_count(handle, value))
            }
            if let value = configuration.invertedToForwardScanRatio {
                try CAPI.check(zvec_config_data_set_invert_to_forward_scan_ratio(handle, value))
            }
            if let value = configuration.bruteForceByKeysRatio {
                try CAPI.check(zvec_config_data_set_brute_force_by_keys_ratio(handle, value))
            }
            if let value = configuration.fullTextBruteForceByKeysRatio {
                try CAPI.check(zvec_config_data_set_fts_brute_force_by_keys_ratio(handle, value))
            }
            if let url = configuration.jiebaDictionaryDirectory {
                try url.path.withCString {
                    try CAPI.check(zvec_config_data_set_jieba_dict_dir(handle, $0))
                }
            }
            if let log = configuration.log {
                let logHandle = try Self.makeLog(log)
                let status = zvec_config_data_set_log_config(handle, logHandle)
                if status != ZVEC_OK { zvec_config_log_destroy(logHandle) }
                try CAPI.check(status)
            }
        } catch {
            zvec_config_data_destroy(handle)
            self.handle = nil
            throw error
        }
    }

    borrowing func withHandle<Result>(
        _ body: (OpaquePointer?) throws -> Result
    ) throws -> Result {
        try body(handle)
    }

    private static func makeLog(_ configuration: LogConfiguration) throws -> OpaquePointer {
        let result: OpaquePointer?
        switch configuration {
        case let .console(level):
            result = zvec_config_log_create_console(zvec_log_level_t(rawValue: UInt32(level.rawValue)))
        case let .file(level, directory, baseName, fileSize, days):
            result = directory.path.withCString { directory in
                baseName.withCString { baseName in
                    zvec_config_log_create_file(
                        zvec_log_level_t(rawValue: UInt32(level.rawValue)),
                        directory,
                        baseName,
                        fileSize,
                        days
                    )
                }
            }
        }
        guard let result else { throw CAPI.error(for: ZVEC_ERROR_INVALID_ARGUMENT) }
        return result
    }

    deinit {
        if let handle { zvec_config_data_destroy(handle) }
    }
}
