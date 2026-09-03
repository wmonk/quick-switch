import Foundation

/// Maintains a most-recently-used ordering while allowing the caller to
/// reconcile the set of live identifiers without throwing away history.
struct WindowMRU<Identifier: Hashable> {
    private(set) var identifiers: [Identifier] = []

    mutating func recordUse(of identifier: Identifier) {
        guard identifiers.first != identifier else { return }
        if let existingIndex = identifiers.firstIndex(of: identifier) {
            identifiers.remove(at: existingIndex)
        }
        identifiers.insert(identifier, at: 0)
    }

    mutating func reconcile(with liveIdentifiers: [Identifier]) {
        let live = Set(liveIdentifiers)
        identifiers.removeAll { !live.contains($0) }

        let known = Set(identifiers)
        identifiers.append(contentsOf: liveIdentifiers.filter { !known.contains($0) })
    }
}
