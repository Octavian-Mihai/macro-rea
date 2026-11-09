import AppIntents

/// "Add food" request shared between the widget and the app through the App Group.
enum AddFoodRequest {
    private static let key = "pendingAddFood"
    static func make() { Theme.store.set(true, forKey: key) }
    /// True once if a widget asked to add food; the flag is cleared when read.
    static func take() -> Bool {
        guard Theme.store.bool(forKey: key) else { return false }
        Theme.store.set(false, forKey: key)
        return true
    }
}

/// The widget's + button: opens the app, which then shows the add-food screen.
struct OpenAddFoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Add food"
    static var description = IntentDescription("Open Macros to search and log a food.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        AddFoodRequest.make()
        return .result()
    }
}
