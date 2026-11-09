import SwiftUI
import Charts

/// Track split into "eaten" and "left" segments. Eaten mode: eaten is the solid colour, left is soft.
/// Left mode: the two swap.
struct Ring: View {
    let fraction: Double      // eaten / target
    let color: Color
    var lineWidth: CGFloat = 10
    var showLeft = false
    var body: some View {
        let e = min(1, max(0, fraction))
        let eatenColor = fraction > 1.0001 ? Color.red : color
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        ZStack {
            Circle().trim(from: e, to: 1).stroke(showLeft ? color : color.opacity(0.2), style: style)
            Circle().trim(from: 0, to: e).stroke(showLeft ? eatenColor.opacity(0.2) : eatenColor, style: style)
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
    }
}

/// Horizontal version of `Ring`.
struct SplitBar: View {
    let fraction: Double
    let color: Color
    let showLeft: Bool
    var height: CGFloat = 14
    var body: some View {
        GeometryReader { geo in
            let e = min(1, max(0, fraction))
            let eatenColor = fraction > 1.0001 ? Color.red : color
            HStack(spacing: 0) {
                Rectangle().fill(showLeft ? eatenColor.opacity(0.2) : eatenColor).frame(width: geo.size.width * e)
                Rectangle().fill(showLeft ? color : color.opacity(0.2))
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

struct DayTotals {
    var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
    init(_ entries: [FoodEntry] = []) {
        for e in entries { calories += e.calories; protein += e.protein; carbs += e.carbs; fat += e.fat }
    }
}

/// Everything a chart needs for the selected day.
extension DayTotals {
    static func micros(_ entries: [FoodEntry]) -> Micros { entries.reduce(Micros()) { $0 + $1.micros } }
}

struct ChartData {
    let day: Date
    let entries: [FoodEntry]
    let week: [(day: Date, totals: DayTotals)]   // 7 days ending on `day`
    let totals: DayTotals
    let targets: Targets
    let showLeft: Bool
}

enum ChartKind: String, CaseIterable, Identifiable {
    case rings, bars, donut, meals, timeline, week, weekMacros, micros
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rings: "Rings"
        case .bars: "Bars"
        case .donut: "Split"
        case .meals: "Meals"
        case .timeline: "Timeline"
        case .week: "7 days"
        case .weekMacros: "Macros 7d"
        case .micros: "Micros"
        }
    }
    var icon: String {
        switch self {
        case .rings: "circle.circle"
        case .bars: "chart.bar.fill"
        case .donut: "chart.pie.fill"
        case .meals: "fork.knife"
        case .timeline: "chart.line.uptrend.xyaxis"
        case .week: "calendar"
        case .weekMacros: "chart.bar.xaxis"
        case .micros: "leaf"
        }
    }
}

// MARK: - Rings

struct RingsChart: View {
    let d: ChartData
    var body: some View {
        let leftCal = d.targets.calories - d.totals.calories
        VStack(spacing: 16) {
            ZStack {
                Ring(fraction: d.totals.calories / max(1, d.targets.calories), color: Palette.calories, lineWidth: 16, showLeft: d.showLeft)
                VStack(spacing: 0) {
                    Text(d.showLeft ? abs(leftCal).kcalText : d.totals.calories.kcalText)
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(d.showLeft && leftCal < 0 ? .red : .primary)
                    Text(d.showLeft ? (leftCal >= 0 ? "kcal left" : "kcal over") : "kcal eaten").font(.caption).foregroundStyle(.secondary)
                    Text("of \(d.targets.calories.kcalText)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 180, height: 180)
            HStack(spacing: 8) {
                MacroRing(name: "Protein", eaten: d.totals.protein, target: d.targets.protein, color: Palette.protein, showLeft: d.showLeft)
                MacroRing(name: "Carbs", eaten: d.totals.carbs, target: d.targets.carbs, color: Palette.carbs, showLeft: d.showLeft)
                MacroRing(name: "Fat", eaten: d.totals.fat, target: d.targets.fat, color: Palette.fat, showLeft: d.showLeft)
            }
        }
    }
}

struct MacroRing: View {
    let name: String, eaten: Double, target: Double, color: Color, showLeft: Bool
    var body: some View {
        let left = target - eaten
        VStack(spacing: 6) {
            ZStack {
                Ring(fraction: eaten / max(1, target), color: color, lineWidth: 7, showLeft: showLeft)
                Text(showLeft ? (left >= 0 ? "\(Int(left.rounded()))" : "+\(Int((-left).rounded()))") : "\(Int(eaten.rounded()))")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(showLeft && left < 0 ? .red : .primary)
            }
            .frame(width: 66, height: 66)
            Text(name).font(.caption.weight(.medium))
            Text(showLeft ? "g left of \(Int(target.rounded()))" : "of \(Int(target.rounded())) g")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bars

struct BarsChart: View {
    let d: ChartData
    var body: some View {
        VStack(spacing: 18) {
            row("Calories", d.totals.calories, d.targets.calories, Palette.calories, unit: "kcal")
            row("Protein", d.totals.protein, d.targets.protein, Palette.protein, unit: "g")
            row("Carbs", d.totals.carbs, d.targets.carbs, Palette.carbs, unit: "g")
            row("Fat", d.totals.fat, d.targets.fat, Palette.fat, unit: "g")
        }
    }
    private func row(_ name: String, _ eaten: Double, _ target: Double, _ color: Color, unit: String) -> some View {
        let left = target - eaten
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(d.showLeft ? (left >= 0 ? "\(Int(left.rounded())) \(unit) left" : "\(Int((-left).rounded())) \(unit) over")
                                : "\(Int(eaten.rounded())) / \(Int(target.rounded())) \(unit)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(d.showLeft && left < 0 ? .red : .secondary)
            }
            SplitBar(fraction: eaten / max(1, target), color: color, showLeft: d.showLeft)
        }
    }
}

// MARK: - Split donut

struct DonutChart: View {
    let d: ChartData
    private struct Slice: Identifiable { var id: String { name }; var name: String; var kcal: Double }
    private var slices: [Slice] {
        let t = d.totals, g = d.targets
        if d.showLeft {
            return [Slice(name: "Protein", kcal: max(0, (g.protein - t.protein) * 4)), Slice(name: "Carbs", kcal: max(0, (g.carbs - t.carbs) * 4)),
                    Slice(name: "Fat", kcal: max(0, (g.fat - t.fat) * 9))]
        }
        return [Slice(name: "Protein", kcal: t.protein * 4), Slice(name: "Carbs", kcal: t.carbs * 4), Slice(name: "Fat", kcal: t.fat * 9)]
    }
    var body: some View {
        let total = slices.reduce(0) { $0 + $1.kcal }
        VStack(spacing: 10) {
            if total <= 0 { Text(d.showLeft ? "All macro targets reached" : "Nothing logged yet").foregroundStyle(.secondary).frame(height: 200) }
            else {
                Chart(slices) { s in
                    SectorMark(angle: .value("kcal", s.kcal), innerRadius: .ratio(0.62), angularInset: 2)
                        .cornerRadius(5).foregroundStyle(by: .value("Macro", s.name))
                        .annotation(position: .overlay) {
                            if s.kcal / total > 0.08 { Text("\(Int((s.kcal / total * 100).rounded()))%").font(.caption.bold()).foregroundStyle(.white) }
                        }
                }
                .chartForegroundStyleScale(["Protein": Palette.protein, "Carbs": Palette.carbs, "Fat": Palette.fat])
                .chartLegend(position: .bottom)
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text(total.kcalText).font(.title2.bold().monospacedDigit())
                        Text(d.showLeft ? "kcal to fill" : "kcal from macros").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 240)
            }
            Text(d.showLeft ? "Calories still available per macro, based on your targets." : "Share of today's calories from protein, carbs and fat.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Meals

struct MealsChart: View {
    let d: ChartData
    private struct Row: Identifiable { var id = UUID(); var meal: String; var macro: String; var kcal: Double }
    private var rows: [Row] {
        Meal.allCases.flatMap { m -> [Row] in
            let es = d.entries.filter { $0.meal == m }
            return [Row(meal: m.title, macro: "Protein", kcal: es.reduce(0) { $0 + $1.protein } * 4),
                    Row(meal: m.title, macro: "Carbs", kcal: es.reduce(0) { $0 + $1.carbs } * 4),
                    Row(meal: m.title, macro: "Fat", kcal: es.reduce(0) { $0 + $1.fat } * 9)]
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(rows) { r in
                BarMark(x: .value("kcal", r.kcal), y: .value("Meal", r.meal)).foregroundStyle(by: .value("Macro", r.macro))
            }
            .chartForegroundStyleScale(["Protein": Palette.protein, "Carbs": Palette.carbs, "Fat": Palette.fat])
            .chartYScale(domain: Meal.allCases.map(\.title))
            .chartLegend(position: .bottom)
            .frame(height: 230)
            Text("Calories per meal, split by macro.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Timeline

struct TimelineChart: View {
    let d: ChartData
    private struct Pt: Identifiable { var id = UUID(); var t: Date; var eaten: Double }
    private var points: [Pt] {
        let start = d.day, end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        var cum = 0.0
        var out = [Pt(t: start, eaten: 0)]
        for e in d.entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            let t = min(max(e.timestamp, start), end)
            out.append(Pt(t: t, eaten: cum))   // step at the meal
            cum += e.calories
            out.append(Pt(t: t, eaten: cum))
        }
        let now = Calendar.current.isDateInToday(d.day) ? min(max(.now, start), end) : end
        out.append(Pt(t: now, eaten: cum))
        return out
    }
    var body: some View {
        let start = d.day, end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let hard = Palette.calories, soft = Palette.calories.opacity(0.28)
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Time", p.t), y: .value("kcal", p.eaten), series: .value("S", "Eaten"))
                        .foregroundStyle(d.showLeft ? soft : hard).lineStyle(StrokeStyle(lineWidth: d.showLeft ? 2 : 3.5))
                    LineMark(x: .value("Time", p.t), y: .value("kcal", d.targets.calories - p.eaten), series: .value("S", "Left"))
                        .foregroundStyle(d.showLeft ? hard : soft).lineStyle(StrokeStyle(lineWidth: d.showLeft ? 3.5 : 2))
                }
                RuleMark(y: .value("Goal", d.targets.calories)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(position: .top, alignment: .trailing) { Text("goal").font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXScale(domain: start...end)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
            .frame(height: 230)
            Text("Eaten rises, left falls. The highlighted line follows the toggle.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 7 days

struct WeekChart: View {
    let d: ChartData
    private struct Seg: Identifiable { var id = UUID(); var day: Date; var kind: String; var kcal: Double }
    private var segs: [Seg] {
        d.week.flatMap { w -> [Seg] in
            let e = w.totals.calories, g = d.targets.calories
            guard e > 0 else { return [Seg(day: w.day, kind: "Left", kcal: 0)] }
            return [Seg(day: w.day, kind: "Eaten", kcal: min(e, g)), Seg(day: w.day, kind: "Over", kcal: max(0, e - g)),
                    Seg(day: w.day, kind: "Left", kcal: max(0, g - e))]
        }
    }
    var body: some View {
        let hard = Palette.calories, soft = Palette.calories.opacity(0.25)
        VStack(alignment: .leading, spacing: 8) {
            Chart(segs) { s in
                BarMark(x: .value("Day", s.day, unit: .day), y: .value("kcal", s.kcal)).foregroundStyle(by: .value("Part", s.kind))
            }
            .chartForegroundStyleScale(["Eaten": d.showLeft ? soft : hard, "Left": d.showLeft ? hard : soft, "Over": Color.red])
            .chartLegend(position: .bottom)
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 230)
            let logged = d.week.filter { $0.totals.calories > 0 }
            if !logged.isEmpty {
                Text("Average \((logged.reduce(0) { $0 + $1.totals.calories } / Double(logged.count)).kcalText) kcal on logged days · goal \(d.targets.calories.kcalText)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct WeekMacrosChart: View {
    let d: ChartData
    private struct Row: Identifiable { var id = UUID(); var day: Date; var macro: String; var kcal: Double }
    var body: some View {
        let rows = d.week.flatMap { w in
            [Row(day: w.day, macro: "Protein", kcal: w.totals.protein * 4), Row(day: w.day, macro: "Carbs", kcal: w.totals.carbs * 4),
             Row(day: w.day, macro: "Fat", kcal: w.totals.fat * 9)]
        }
        VStack(alignment: .leading, spacing: 8) {
            Chart(rows) { r in
                BarMark(x: .value("Day", r.day, unit: .day), y: .value("kcal", r.kcal)).foregroundStyle(by: .value("Macro", r.macro))
            }
            .chartForegroundStyleScale(["Protein": Palette.protein, "Carbs": Palette.carbs, "Fat": Palette.fat])
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .chartLegend(position: .bottom)
            .frame(height: 230)
            Text("Where each day's calories came from.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Micronutrients

struct MicrosChart: View {
    let d: ChartData
    var body: some View {
        let total = d.entries.reduce(Micros()) { $0 + $1.micros }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(total.rows) { r in
                let frac = r.value / r.daily
                let limit = ["Sodium", "Sugar", "Saturated fat"].contains(r.name)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(r.name).font(.subheadline)
                        Spacer()
                        Text(d.showLeft ? "\(Int((max(0, 1 - frac) * 100).rounded()))% left of daily value" : "\(Int((frac * 100).rounded()))% of daily value").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    SplitBar(fraction: frac, color: limit ? .orange : .green, showLeft: d.showLeft, height: 8)
                }
            }
            if d.entries.allSatisfy({ $0.micros == Micros() }) {
                Text("No micronutrient data on today's foods yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
