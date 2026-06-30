import Foundation

public enum LogConfiguration: Sendable, Equatable {
    case console(level: LogLevel = .warning)
    case file(
        level: LogLevel = .warning,
        directory: URL,
        baseName: String = "zvec",
        maximumFileSizeMB: UInt32 = 64,
        retentionDays: UInt32 = 7
    )
}

public struct Configuration: Sendable, Equatable {
    public var memoryLimitBytes: UInt64?
    public var log: LogConfiguration?
    public var queryThreadCount: UInt32?
    public var optimizeThreadCount: UInt32?
    public var invertedToForwardScanRatio: Float?
    public var bruteForceByKeysRatio: Float?
    public var fullTextBruteForceByKeysRatio: Float?
    public var jiebaDictionaryDirectory: URL?

    public init(
        memoryLimitBytes: UInt64? = nil,
        log: LogConfiguration? = nil,
        queryThreadCount: UInt32? = nil,
        optimizeThreadCount: UInt32? = nil,
        invertedToForwardScanRatio: Float? = nil,
        bruteForceByKeysRatio: Float? = nil,
        fullTextBruteForceByKeysRatio: Float? = nil,
        jiebaDictionaryDirectory: URL? = nil
    ) {
        self.memoryLimitBytes = memoryLimitBytes
        self.log = log
        self.queryThreadCount = queryThreadCount
        self.optimizeThreadCount = optimizeThreadCount
        self.invertedToForwardScanRatio = invertedToForwardScanRatio
        self.bruteForceByKeysRatio = bruteForceByKeysRatio
        self.fullTextBruteForceByKeysRatio = fullTextBruteForceByKeysRatio
        self.jiebaDictionaryDirectory = jiebaDictionaryDirectory
    }
}

public struct CollectionOptions: Sendable, Equatable {
    public var enableMemoryMapping: Bool
    public var maximumBufferSize: Int?
    public var readOnly: Bool

    public init(
        enableMemoryMapping: Bool = true,
        maximumBufferSize: Int? = nil,
        readOnly: Bool = false
    ) {
        self.enableMemoryMapping = enableMemoryMapping
        self.maximumBufferSize = maximumBufferSize
        self.readOnly = readOnly
    }
}

public struct ZvecCapabilities: Sendable, Equatable {
    public let hnsw = true
    public let ivf = true
    public let flat = true
    public let inverted = true
    public let fullTextSearch = true
    public let vamana = false

    public init() {}
}
