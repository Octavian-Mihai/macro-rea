import Foundation
import WidgetKit

/// Today's numbers, shared from the app to the widget through an App Group.
struct WidgetSnapshot: Codable {
    var day: Date
    var calories: Double, calTarget: Double
    var protein: Double, pTarget: Double
    var carbs: Double, cTarget: Double
    var fat: Double, fTarget: Double

    static let group = "group.com.octa.macros"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
