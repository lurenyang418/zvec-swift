import Foundation

extension Array where Element == String {
    func withCStringArray<Result>(
        _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?) throws -> Result
    ) throws -> Result {
        var storage: [UnsafeMutablePointer<CChar>] = []
        storage.reserveCapacity(count)
        do {
            for value in self {
                guard let pointer = strdup(value) else {
                    throw ZvecError(
                        code: .resourceExhausted,
                        message: "Unable to allocate a native string array"
                    )
                }
                storage.append(pointer)
            }
        } catch {
            storage.forEach { free($0) }
            throw error
        }
        defer { storage.forEach { free($0) } }

        var pointers = storage.map { Optional(UnsafePointer<CChar>($0)) }
        return try pointers.withUnsafeMutableBufferPointer {
            try body($0.baseAddress)
        }
    }
}
