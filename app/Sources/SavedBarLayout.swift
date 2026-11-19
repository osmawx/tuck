import Foundation

/// Stores the user's logical order separately from macOS's temporary divider positions.
struct SavedBarLayout: Codable {
    private static let ORDER_KEY = "HiderSavedBarOrder"
    private static let DIVIDERS_KEY = "HiderCompactStatusItemPositions"

    private let itemIDsBySection: [BarSection: [String]]

    /// Keeps unavailable icons in storage so they can return to their saved section later.
    init(sections: [BarSection: [MenuBarItem]], previous: SavedBarLayout? = nil) {
        let activeItems = Dictionary(grouping: sections.values.joined(), by: \.layoutID)
        self.itemIDsBySection = Dictionary(uniqueKeysWithValues: BarSection.allCases.map { section in
            var identifiers = sections[section, default: []].map(\.layoutID).filter { activeItems[$0]?.count == 1 }
            // Anchor absent icons to the next surviving icon in their previous section.
            var followingID: String?
            for identifier in (previous?.itemIDsBySection[section] ?? []).reversed() {
                if identifiers.contains(identifier) {
                    followingID = identifier
                } else if activeItems[identifier] == nil {
                    let index = followingID.flatMap { identifiers.firstIndex(of: $0) } ?? identifiers.endIndex
                    identifiers.insert(identifier, at: index)
                    followingID = identifier
                }
            }
            return (section, identifiers)
        })
    }

    /// Reads the last explicitly applied arrangement.
    static func load(from defaults: UserDefaults = .standard) -> SavedBarLayout? {
        guard let data = defaults.data(forKey: ORDER_KEY) else { return nil }
        return try? PropertyListDecoder().decode(Self.self, from: data)
    }

    /// Saves the arrangement independently of external app preferences.
    func save(to defaults: UserDefaults = .standard) {
        if let data = try? PropertyListEncoder().encode(self) {
            defaults.set(data, forKey: Self.ORDER_KEY)
        }
    }

    /// Restores known icons and keeps newly discovered icons in their current sections.
    func restoredSections(from actual: [BarSection: [MenuBarItem]]) -> [BarSection: [MenuBarItem]] {
        let byID = Dictionary(grouping: actual.values.joined(), by: \.layoutID)
        // An ambiguous window name must never move two items into the same slot.
        let unambiguousItems = byID.compactMapValues { $0.count == 1 ? $0.first : nil }
        let reservedIDs = Set(itemIDsBySection.values.joined()).intersection(unambiguousItems.keys)
        return Dictionary(uniqueKeysWithValues: BarSection.allCases.map { section in
            let savedItems = itemIDsBySection[section, default: []].compactMap { unambiguousItems[$0] }
            return (section, savedItems + actual[section, default: []].filter { !reservedIDs.contains($0.layoutID) })
        })
    }

    /// Associates each unambiguous saved icon with its currently running process.
    func presentProcesses(in actual: [BarSection: [MenuBarItem]]) -> [String: pid_t] {
        let itemsByID = Dictionary(grouping: actual.values.joined(), by: \.layoutID)
        return Dictionary(uniqueKeysWithValues: Set(itemIDsBySection.values.joined()).compactMap { identifier in
            guard let items = itemsByID[identifier], items.count == 1 else { return nil }
            return (identifier, items[0].processIdentifier)
        })
    }

    /// Writes compact positions and preserves a separate copy before AppKit updates its keys.
    static func saveCompactPositions(_ positions: [String: Double], to defaults: UserDefaults = .standard) {
        defaults.set(positions, forKey: DIVIDERS_KEY)
        restoreCompactPositions(in: defaults)
    }

    /// Seeds AppKit's preferred positions before it registers Tuck's status items.
    static func restoreCompactPositions(in defaults: UserDefaults = .standard) {
        guard let positions = defaults.dictionary(forKey: DIVIDERS_KEY) as? [String: Double] else { return }
        for (key, position) in positions { defaults.set(position, forKey: key) }
        defaults.synchronize()
    }
}
