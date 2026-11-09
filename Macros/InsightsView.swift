import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query private var weights: [WeightEntry]
    @Query private var entries: [FoodEntry]
    @AppStorage(Keys.useLbs) private var useLbs = false
    private var reader = ProfileReader()

    private struct Day: Identifiable { var id: Date { day }; var day: Date; var kcal: Double; var p: Double; var c: Double; var f: Double }

    private var last14: [Day] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<14).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: today)!
            let es = entries.filter { $0.day == d }
            return Day(day: d, kcal: es.reduce(0) { $0 + $1.calories }, p: es.reduce(0) { $0 + $1.protein },
                       c: es.reduce(0) { $0 + $1.carbs }, f: es.reduce(0) { $0 + $1.fat })
        }
    }

    var body: some View {
        let plan = Plan.make(weights: weights, entries: entries, profile: reader.profile, applied: reader.applied)
        let days = last14
        let logged = days.suffix(7).filter { $0.kcal > 0 }
        NavigationStack {
            List {
                Section { NavigationLink { CheckInView() } label: { Label("Weekly check-in", systemImage: "checkmark.seal") } }
                Section("Expenditure (TDEE)") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(plan.expenditure.kcal.kcalText).font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("kcal/day").foregroundStyle(.secondary)
                    }
                    ProgressView(value: plan.expenditure.confidence) { Text("Data confidence").font(.caption) }.tint(.green)
                    Text(plan.expenditure.confidence < 0.05
                         ? "Using a formula estimate (\(plan.expenditure.formulaKcal.kcalText) kcal). Log food and weight for 7+ days and it adapts to you."
                         : "Adapted from \(plan.expenditure.loggedDays) logged days and your weight trend. Formula baseline: \(plan.expenditure.formulaKcal.kcalText) kcal.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Current targets") {
                    LabeledContent("Calories", value: plan.targets.calories.kcalText + " kcal")
                    LabeledContent("Protein", value: plan.targets.protein.gText)
                    LabeledContent("Carbs", value: plan.targets.carbs.gText)
                    LabeledContent("Fat", value: plan.targets.fat.gText)
                    Text(goalText(plan)).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Calories — last 14 days") {
                    Chart {
                        ForEach(days) { d in
                            BarMark(x: .value("Day", d.day, unit: .day), y: .value("kcal", d.kcal)).foregroundStyle(Palette.calories)
                        }
                        RuleMark(y: .value("Target", plan.targets.calories)).foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }.frame(height: 180)
                }
                if !logged.isEmpty {
                    Section("7-day average (logged days)") {
                        let n = Double(logged.count)
                        LabeledContent("Calories", value: (logged.reduce(0) { $0 + $1.kcal } / n).kcalText + " kcal")
                        LabeledContent("Protein", value: (logged.reduce(0) { $0 + $1.p } / n).gText)
                        LabeledContent("Carbs", value: (logged.reduce(0) { $0 + $1.c } / n).gText)
                        LabeledContent("Fat", value: (logged.reduce(0) { $0 + $1.f } / n).gText)
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }

    private func goalText(_ plan: Plan) -> String {
        let r = plan.profile.goalRateKgPerWeek
        let u = Units.label(lbs: useLbs)
        let shown = abs(Units.display(r, lbs: useLbs))
        if abs(r) < 0.01 { return "Goal: maintain weight." }
        return String(format: "Goal: %@ %.2f %@/week.", r < 0 ? "lose" : "gain", shown, u)
    }
}
