import Foundation

/// A failure reported by Zvec or by the Swift lifetime and validation layer.
public struct ZvecError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: Sendable, Equatable {
        case notFound
        case alreadyExists
        case invalidArgument
        case permissionDenied
        case failedPrecondition
        case resourceExhausted
        case unavailable
        case internalError
        case notSupported
        case unknown(Int32)
        case closed
        case cancelled
        case incompatibleNativeVersion(required: String, actual: String)
    }

    public let code: Code
    public let message: String
    public let sourceFile: String?
    public let sourceLine: Int?
    public let sourceFunction: String?

    public init(
        code: Code,
        message: String,
        sourceFile: String? = nil,
        sourceLine: Int? = nil,
        sourceFunction: String? = nil
    ) {
        self.code = code
        self.message = message
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
        self.sourceFunction = sourceFunction
    }

    public var description: String {
        guard let sourceFile else { return "\(code): \(message)" }
        let location = sourceLine.map { "\(sourceFile):\($0)" } ?? sourceFile
        return "\(code): \(message) (\(location))"
    }

    static func invalid(_ message: String) -> ZvecError {
        ZvecError(code: .invalidArgument, message: message)
    }
}
