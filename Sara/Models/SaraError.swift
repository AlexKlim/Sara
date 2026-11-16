import Foundation

struct SaraError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
