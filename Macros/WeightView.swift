import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @Environment(\.modelContext) private var ctx
    @AppStorage(Keys.useLbs) private var useLbs = false
    @AppStorage(Keys.healthSync) private var healthSync = false
    @State private var text = ""
    @State private var date = Date()

    private var tr: [(day: Date, trend: Double, raw: Double?)] { Engine.trend(weights) }

    var body: some View {
        NavigationStack {
            List {
                Section("Log weight") {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    HStack {
                        TextField("Weight (\(Units.label(lbs: useLbs)))", text: $text).keyboardType(.decimalPad)
                        Button("Save", action: save).buttonStyle(.borderedProminent)
                            .disabled(Double(text.replacingOccurrences(of: ",", with: ".")) == nil)
                    }
                }
                if let last = tr.last {
                    Section("Trend") {
                        LabeledContent("Trend weight", value: fmt(last.trend))
                        if let w = Engine.weeklyChange(weights) {
                            LabeledContent("Last 7 days", value: String(format: "%+.2f %@", Units.display(w, lbs: useLbs), Units.label(lbs: useLbs)))
                        }
                    }
                    Section { WeightChart(points: Array(tr.suffix(90)), lbs: useLbs).frame(height: 220) }
                }
                Section("History") {
                    ForEach(weights) { w in
                        HStack { Text(w.day.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text(fmt(w.kg)) }
                    }
                    .onDelete { idx in idx.forEach { ctx.delete(weights[$0]) } }
                }
            }
            .navigationTitle("Weight")
            .task { if healthSync { await Health.shared.importWeights(into: ctx) } }
        }
    }

    private func fmt(_ kg: Double) -> String {
        String(format: "%.1f %@", Units.display(kg, lbs: useLbs), Units.label(lbs: useLbs))
    }

    private func save() {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")) else { return }
        let kg = Units.toKg(v, lbs: useLbs)
        let d = Calendar.current.startOfDay(for: date)
        if let existing = weights.first(where: { $0.day == d }) { existing.kg = kg } else { ctx.insert(WeightEntry(day: d, kg: kg)) }
        text = ""
        if healthSync { Task { await Health.shared.saveWeight(kg: kg, date: date) } }
    }
}

struct WeightChart: View {
    let points: [(day: Date, trend: Double, raw: Double?)]
    let lbs: Bool
    var body: some View {
        Chart {
            ForEach(points, id: \.day) { p in
                if let r = p.raw {
                    PointMark(x: .value("Day", p.day), y: .value("Weight", Units.display(r, lbs: lbs)))
                        .foregroundStyle(.gray.opacity(0.6)).symbolSize(25)
                }
                LineMark(x: .value("Day", p.day), y: .value("Trend", Units.display(p.trend, lbs: lbs)))
                    .foregroundStyle(.green).interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
