import Foundation

/// The selection behavior shared by both global and in-application switchers.
struct SelectionCycle<Element> {
    let elements: [Element]
    private(set) var selectedIndex: Int

    init(elements: [Element], reverse: Bool) {
        self.elements = elements

        guard elements.count > 1 else {
            selectedIndex = 0
            return
        }

        // A forward invocation picks the previous MRU item. A reverse
        // invocation starts at the other end of the ordering.
        selectedIndex = reverse ? elements.count - 1 : 1
    }

    var selected: Element? {
        guard elements.indices.contains(selectedIndex) else { return nil }
        return elements[selectedIndex]
    }

    mutating func advance(reverse: Bool) {
        guard !elements.isEmpty else { return }
        let delta = reverse ? -1 : 1
        selectedIndex = (selectedIndex + delta + elements.count) % elements.count
    }

    mutating func select(index: Int) {
        guard elements.indices.contains(index) else { return }
        selectedIndex = index
    }
}
