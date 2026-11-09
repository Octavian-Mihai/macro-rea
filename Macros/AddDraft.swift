import Foundation

/// Work-in-progress "add food" input, saved to disk as the user types so it survives the app being closed.
/// It is cleared when the food is logged or the sheet is dismissed, and ignored after 12 hours.
struct AddDraft: Codable {
    var meal = Meal.snacks.rawValue
    var day = Date()
    var query = ""
    var selected: FoodItem?
    var qtyText: String?
    var unit: String?
    var customFields: [String: String]?
    var customOpen = false
    var savedAt = Date()

    private static let key = "addFoodDraft"

    var isMeaningful: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || selected != nil
            || !(customFields ?? [:]).filter({ $0.key != "serving" && $0.key != "saveIt" && !$0.value.isEmpty }).isEmpty
    }

    static func load() -> AddDraft? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let d = try? JSONDecoder().decode(AddDraft.self, from: data),
              Date().timeIntervalSince(d.savedAt) < 12 * 3600, d.isMeaningful else { return nil }
        return d
    }

    /// Mutate the stored draft (creating it if needed); an empty draft is removed.
    static func update(_ change: (inout AddDraft) -> Void) {
        var d = (try? UserDefaults.standard.data(forKey: key).flatMap { try JSONDecoder().decode(AddDraft.self, from: $0) }) ?? AddDraft()
        change(&d)
        d.savedAt = Date()
        if d.isMeaningful, let data = try? JSONEncoder().encode(d) { UserDefaults.standard.set(data, forKey: key) }
        else { clear() }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
