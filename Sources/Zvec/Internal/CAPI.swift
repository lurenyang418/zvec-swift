internal import CZvec
import Foundation

enum CAPI {
    static let minimumVersion = (major: 0, minor: 5, patch: 1)

    static func check(_ status: zvec_error_code_t) throws(ZvecError) {
        guard status != ZVEC_OK else { return }
        throw error(for: status)
    }

    static func typed<Result>(_ operation: () throws -> Result) throws(ZvecError) -> Result {
        do {
            return try operation()
        } catch let error as ZvecError {
            throw error
        } catch {
            throw ZvecError(code: .internalError, message: String(describing: error))
        }
    }

    static func coerce(_ error: any Error) -> ZvecError {
        if let error = error as? ZvecError { return error }
        return ZvecError(code: .internalError, message: String(describing: error))
    }

    static func error(for status: zvec_error_code_t) -> ZvecError {
        var details = zvec_error_details_t()
        _ = zvec_get_last_error_details(&details)
        let code = code(for: status)
        let fallback = zvec_error_code_to_string(status).map(String.init(cString:))
        let message = details.message.map(String.init(cString:)) ?? fallback ?? "Unknown Zvec error"
        return ZvecError(
            code: code,
            message: message,
            sourceFile: details.file.map(String.init(cString:)),
            sourceLine: details.line > 0 ? Int(details.line) : nil,
            sourceFunction: details.function.map(String.init(cString:))
        )
    }

    static func code(for status: zvec_error_code_t) -> ZvecError.Code {
        switch status {
        case ZVEC_ERROR_NOT_FOUND: .notFound
        case ZVEC_ERROR_ALREADY_EXISTS: .alreadyExists
        case ZVEC_ERROR_INVALID_ARGUMENT: .invalidArgument
        case ZVEC_ERROR_PERMISSION_DENIED: .permissionDenied
        case ZVEC_ERROR_FAILED_PRECONDITION: .failedPrecondition
        case ZVEC_ERROR_RESOURCE_EXHAUSTED: .resourceExhausted
        case ZVEC_ERROR_UNAVAILABLE: .unavailable
        case ZVEC_ERROR_INTERNAL_ERROR: .internalError
        case ZVEC_ERROR_NOT_SUPPORTED: .notSupported
        default: .unknown(Int32(bitPattern: status.rawValue))
        }
    }

    static func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map(String.init(cString:))
    }

    static func int32(_ value: Int, named name: String) throws(ZvecError) -> Int32 {
        guard let result = Int32(exactly: value) else {
            throw .invalid("\(name) must fit in a signed 32-bit integer")
        }
        return result
    }

    static func int32(_ value: UInt32, named name: String) throws(ZvecError) -> Int32 {
        guard let result = Int32(exactly: value) else {
            throw .invalid("\(name) must fit in a signed 32-bit integer")
        }
        return result
    }
}
