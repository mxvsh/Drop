import Foundation
import Observation

/// Files parked for later. Stored as paths; entries whose files disappear are dropped.
@Observable
final class ShelfStore {
    private(set) var items: [URL] = []

    @ObservationIgnored private let key = "shelf.items"

    init() {
        items = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var isEmpty: Bool { items.isEmpty }

    func add(_ urls: [URL]) {
        for url in urls.map(\.standardizedFileURL) where !items.contains(url) {
            items.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func prune() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing != items {
            items = existing
            save()
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}
