import SwiftUI
import WidgetKit

/// A colour theme. Shared with the widget through the App Group so both always agree.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let calories: Color, protein: Color, carbs: Color, fat: Color
    /// Marks "over goal". Never one of the macro colours; always paired with the word "over" and a symbol.
    let over: Color
    /// Sodium, sugar and other "keep it low" nutrients.
    let limit: Color
    /// App tint: buttons, links, selected tab.
    let accent: Color

    static let storageKey = "theme"
    static let store = UserDefaults(suiteName: WidgetSnapshot.group) ?? .standard

    static var current: Theme { named(store.string(forKey: storageKey) ?? "classic") }
    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
    static func select(_ id: String) {
        store.set(id, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static let all: [Theme] = [
        Theme(id: "classic", name: "Classic",
              calories: .green, protein: .red, carbs: .blue, fat: .orange, over: .purple, limit: .orange, accent: .blue),
        Theme(id: "ocean", name: "Ocean",
              calories: Color(hex: 0x0A9396), protein: Color(hex: 0xE76F51), carbs: Color(hex: 0x1D6FB8),
              fat: Color(hex: 0xE9A100), over: Color(hex: 0xB5179E), limit: Color(hex: 0xE9A100), accent: Color(hex: 0x0A9396)),
        Theme(id: "sunset", name: "Sunset",
              calories: Color(hex: 0xF26B38), protein: Color(hex: 0xD7263D), carbs: Color(hex: 0x7B2CBF),
              fat: Color(hex: 0xE0A100), over: Color(hex: 0x1B998B), limit: Color(hex: 0xE0A100), accent: Color(hex: 0xF26B38)),
        Theme(id: "forest", name: "Forest",
              calories: Color(hex: 0x2D9A57), protein: Color(hex: 0xB5502B), carbs: Color(hex: 0x2A7F9E),
              fat: Color(hex: 0xC99A2E), over: Color(hex: 0x8E44AD), limit: Color(hex: 0xC99A2E), accent: Color(hex: 0x2D9A57)),
        Theme(id: "berry", name: "Berry",
              calories: Color(hex: 0xC2185B), protein: Color(hex: 0xFF6B4A), carbs: Color(hex: 0x5C6BC0),
              fat: Color(hex: 0xF2A900), over: Color(hex: 0x00897B), limit: Color(hex: 0xF2A900), accent: Color(hex: 0xC2185B)),
        Theme(id: "contrast", name: "High contrast",
              calories: Color(hex: 0x007A33), protein: Color(hex: 0xC40000), carbs: Color(hex: 0x0041C4),
              fat: Color(hex: 0xB35900), over: Color(hex: 0x6A0DAD), limit: Color(hex: 0xB35900), accent: Color(hex: 0x0041C4)),
    ]
}

/// Colours the whole app and widget read. They follow the selected theme.
enum Palette {
    static var calories: Color { Theme.current.calories }
    static var protein: Color { Theme.current.protein }
    static var carbs: Color { Theme.current.carbs }
    static var fat: Color { Theme.current.fat }
    static var over: Color { Theme.current.over }
    static var limit: Color { Theme.current.limit }
}

extension Color {
    /// Same colour in light mode; slightly lighter in dark mode so it keeps its contrast on black.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        self.init(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                func lift(_ c: Double) -> CGFloat { CGFloat(c + (1 - c) * 0.22) }
                return UIColor(red: lift(r), green: lift(g), blue: lift(b), alpha: 1)
            }
            return UIColor(red: r, green: g, blue: b, alpha: 1)
        })
    }
}
