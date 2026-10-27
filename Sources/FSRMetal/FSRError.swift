import Foundation

public enum FSRError: Error, LocalizedError {
    case unavailable(String)
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .invalidInput(message): message
        }
    }
}
