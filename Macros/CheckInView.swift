import SwiftUI
import SwiftData

/// Weekly check-in: compares what happened with the goal and updates targets on request.
struct CheckInView: View {
    @Query private var weights: [WeightEntry]
    @Query private var entries: [FoodEntry]
    @AppStorage(Keys.useLbs) private var useLbs = false
    @Environment(\.dismiss) private var dismiss
    private var reader = ProfileReader()

    var body: some View {
        let profile = reader.profile
        let oldPlan = Plan.make(weights: weights, entries: entries, profile: profile, applied: reader.applied)
        let newPlan = Plan.make(weights: weights, entries: entries, profile: profile, applied: 0)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let week = (1...7).map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let intake = week.map { d in entries.filter { $0.day == d }.reduce(0) { $0 + $1.calories } }.filter { $0 > 0 }
        let avg = intake.isEmpty ? 0 : intake.reduce(0, +) / Double(intake.count)
        let change = Engine.weeklyChange(weights)
        let u = Units.label(lbs: useLbs)

        List {
            Section("Last 7 days") {
                LabeledContent("Days logged", value: "\(intake.count) of 7")
                LabeledContent("Average intake", value: avg > 0 ? avg.kcalText + " kcal" : "—")
                LabeledContent("Trend weight change", value: change.map { String(format: "%+.2f %@", Units.display($0, lbs: useLbs), u) } ?? "Not enough weigh-ins")
                LabeledContent("Goal pace", value: String(format: "%+.2f %@/wk", Units.display(profile.goalRateKgPerWeek, lbs: useLbs), u))
            }
            Section("Expenditure") {
                LabeledContent("Current", value: (reader.applied > 0 ? reader.applied : oldPlan.expenditure.kcal).kcalText + " kcal")
                LabeledContent("Updated estimate", value: newPlan.expenditure.kcal.kcalText + " kcal")
            }
            Section("Targets") {
                row("Calories", oldPlan.targets.calories, newPlan.targets.calories, "")
                row("Protein", oldPlan.targets.protein, newPlan.targets.protein, "g")
                row("Carbs", oldPlan.targets.carbs, newPlan.targets.carbs, "g")
                row("Fat", oldPlan.targets.fat, newPlan.targets.fat, "g")
            }
            if intake.count < 4 {
                Section { Text("Log at least 4 days this week for a reliable update.").font(.footnote).foregroundStyle(.orange) }
            }
            Section {
                Button("Apply new targets") {
                    reader.applied = newPlan.expenditure.kcal
                    reader.lastCheckIn = Date().timeIntervalSince1970
                    dismiss()
                }.bold()
                Button("Keep current targets") {
                    if reader.applied == 0 { reader.applied = oldPlan.expenditure.kcal }
                    reader.lastCheckIn = Date().timeIntervalSince1970
                    dismiss()
                }
            }
        }
        .navigationTitle("Weekly check-in")
    }

    private func row(_ name: String, _ old: Double, _ new: Double, _ unit: String) -> some View {
        LabeledContent(name) {
            HStack(spacing: 4) {
                Text("\(Int(old.rounded()))").foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text("\(Int(new.rounded()))\(unit)").bold()
            }.monospacedDigit()
        }
    }
}
