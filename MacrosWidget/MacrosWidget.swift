import WidgetKit
import SwiftUI

struct MacroEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct Provider: TimelineProvider {
    private var sample: WidgetSnapshot {
        WidgetSnapshot(day: .now, calories: 1240, calTarget: 2200, protein: 95, pTarget: 170, carbs: 130, cTarget: 220, fat: 40, fTarget: 70)
    }
    private func current() -> WidgetSnapshot {
        guard var s = WidgetSnapshot.load() else { return WidgetSnapshot(day: .now, calories: 0, calTarget: 2000, protein: 0, pTarget: 150, carbs: 0, cTarget: 200, fat: 0, fTarget: 65) }
        if !Calendar.current.isDateInToday(s.day) { s.calories = 0; s.protein = 0; s.carbs = 0; s.fat = 0; s.day = .now }
        return s
    }
    func placeholder(in context: Context) -> MacroEntry { MacroEntry(date: .now, snap: sample) }
    func getSnapshot(in context: Context, completion: @escaping (MacroEntry) -> Void) {
        completion(MacroEntry(date: .now, snap: context.isPreview ? sample : current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacroEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        completion(Timeline(entries: [MacroEntry(date: .now, snap: current())], policy: .after(midnight)))
    }
}

struct CalorieRing: View {
    let snap: WidgetSnapshot
    var body: some View {
        let frac = min(1, snap.calories / max(1, snap.calTarget))
        ZStack {
            Circle().stroke(.green.opacity(0.2), lineWidth: 10)
            Circle().trim(from: 0, to: frac).stroke(.green, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(Int(max(0, snap.calTarget - snap.calories).rounded()))).font(.title2.bold().monospacedDigit())
                Text("left").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct MacroLine: View {
    let name: String, value: Double, target: Double, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.caption2); Spacer(); Text("\(Int(value.rounded()))/\(Int(target.rounded()))g").font(.caption2.monospacedDigit()) }
            ProgressView(value: min(1, value / max(1, target))).tint(color)
        }
    }
}

struct MacrosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacroEntry
    var body: some View {
        let s = entry.snap
        switch family {
        case .accessoryCircular:
            Gauge(value: min(1, s.calories / max(1, s.calTarget))) {
                Text("kcal")
            } currentValueLabel: {
                Text(String(Int(max(0, s.calTarget - s.calories).rounded()))).font(.caption)
            }.gaugeStyle(.accessoryCircular)
        case .systemMedium:
            HStack(spacing: 16) {
                CalorieRing(snap: s).padding(4)
                VStack(spacing: 8) {
                    MacroLine(name: "Protein", value: s.protein, target: s.pTarget, color: .red)
                    MacroLine(name: "Carbs", value: s.carbs, target: s.cTarget, color: .blue)
                    MacroLine(name: "Fat", value: s.fat, target: s.fTarget, color: .orange)
                    Text("\(Int(s.calories.rounded())) / \(Int(s.calTarget.rounded())) kcal").font(.caption2).foregroundStyle(.secondary)
                }
            }
        default:
            CalorieRing(snap: s).padding(6)
        }
    }
}

@main
struct MacrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacrosWidget", provider: Provider()) { entry in
            MacrosWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's macros")
        .description("Calories left and macro progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
