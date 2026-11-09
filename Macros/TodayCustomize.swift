import SwiftUI

/// A number the user can pin under the Today chart.
enum Metric: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat, fiber, sugar, satFat, sodium, potassium, calcium, iron, vitaminC
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fiber: "Fiber"
        case .sugar: "Sugar"
        case .satFat: "Sat. fat"
        case .sodium: "Sodium"
        case .potassium: "Potassium"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .vitaminC: "Vitamin C"
        }
    }
    var unit: String {
        switch self {
        case .calories: ""
        case .protein, .carbs, .fat, .fiber, .sugar, .satFat: "g"
        default: "mg"
        }
    }
    var color: Color {
        switch self {
        case .calories: Palette.calories
        case .protein: Palette.protein
        case .carbs: Palette.carbs
        case .fat: Palette.fat
        case .sodium, .sugar, .satFat: Palette.limit
        default: .teal
        }
    }
    var isMacro: Bool { [.calories, .protein, .carbs, .fat].contains(self) }

    func eaten(_ t: DayTotals, _ m: Micros) -> Double {
        switch self {
        case .calories: t.calories
        case .protein: t.protein
        case .carbs: t.carbs
        case .fat: t.fat
        case .fiber: m.fiber
        case .sugar: m.sugar
        case .satFat: m.satFat
        case .sodium: m.sodium
        case .potassium: m.potassium
        case .calcium: m.calcium
        case .iron: m.iron
        case .vitaminC: m.vitaminC
        }
    }
    /// Macros use the personal plan; micronutrients use approximate daily values.
    func target(_ g: Targets) -> Double {
        switch self {
        case .calories: g.calories
        case .protein: g.protein
        case .carbs: g.carbs
        case .fat: g.fat
        case .fiber: g.fiber
        case .sugar: 50
        case .satFat: 20
        case .sodium: 2300
        case .potassium: 4700
        case .calcium: 1300
        case .iron: 18
        case .vitaminC: 90
        }
    }

    static let defaultList = "fiber,sugar,sodium,satFat"
    static func parse(_ s: String) -> [Metric] {
        let all = s.split(separator: ",").compactMap { Metric(rawValue: String($0)) }
        return Metric.allCases.filter { all.contains($0) }
    }
}

enum TodayPrefs {
    static let metricsKey = "todayMetrics"
    static let chartsKey = "todayCharts"
    static let defaultCharts = ChartKind.allCases.map(\.rawValue).joined(separator: ",")
    static func charts(_ s: String) -> [ChartKind] {
        let on = Set(s.split(separator: ",").map(String.init))
        let list = ChartKind.allCases.filter { on.contains($0.rawValue) }
        return list.isEmpty ? [.rings] : list
    }
}

/// Sheet to choose which chart styles and which numbers appear on the Today tab.
struct CustomizeTodayView: View {
    @AppStorage(TodayPrefs.metricsKey) private var metricsRaw = Metric.defaultList
    @AppStorage(TodayPrefs.chartsKey) private var chartsRaw = TodayPrefs.defaultCharts
    @AppStorage("showCheckInBanner") private var showBanner = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Numbers under the chart") {
                    ForEach(Metric.allCases) { m in
                        Toggle(isOn: bind(m)) {
                            HStack { Circle().fill(m.color).frame(width: 10, height: 10); Text(m.title) }
                        }
                    }
                }
                Section("Chart styles") {
                    ForEach(ChartKind.allCases) { k in
                        Toggle(isOn: bind(k)) { Label(k.title, systemImage: k.icon) }
                    }
                }
                Section {
                    Toggle("Weekly check-in banner", isOn: $showBanner)
                }
                Section {
                    Button("Reset to defaults", role: .destructive) {
                        metricsRaw = Metric.defaultList; chartsRaw = TodayPrefs.defaultCharts; showBanner = true
                    }
                }
            }
            .navigationTitle("Customize Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func bind(_ m: Metric) -> Binding<Bool> {
        Binding(get: { Metric.parse(metricsRaw).contains(m) }, set: { on in
            var cur = Metric.parse(metricsRaw)
            if on { cur.append(m) } else { cur.removeAll { $0 == m } }
            metricsRaw = Metric.allCases.filter(cur.contains).map(\.rawValue).joined(separator: ",")
        })
    }
    private func bind(_ k: ChartKind) -> Binding<Bool> {
        Binding(get: { TodayPrefs.charts(chartsRaw).contains(k) }, set: { on in
            var cur = TodayPrefs.charts(chartsRaw)
            if on { cur.append(k) } else if cur.count > 1 { cur.removeAll { $0 == k } }
            chartsRaw = ChartKind.allCases.filter(cur.contains).map(\.rawValue).joined(separator: ",")
        })
    }
}
