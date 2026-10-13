import Foundation

nonisolated enum DropError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case noSubject
    case noText
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "“\(name)” couldn't be read."
        case .unsupported(let reason): reason
        case .noSubject: "No subject was found to cut out."
        case .noText: "No text was found."
        case .failed(let reason): reason
        }
    }
}
