import SwiftUI
import SwiftData

/// First tab: graphs only. Pick the chart style with the chips; Eaten/Left flips what the charts emphasise.
struct DashboardView: View {
    @Binding var day: Date
    @Query private var weights: [WeightEntry]
    @Query(sort: \FoodEntry.timestamp) private var entries: [FoodEntry]
    @Environment(\.modelContext) private var ctx
    @AppStorage("chartKind") private var kindRaw = ChartKind.rings.rawValue
    @AppStorage("showLeft") private var showLeft = false
    @AppStorage(Keys.healthSync) private var healthSync = false
    @AppStorage(TodayPrefs.metricsKey) private var metricsRaw = Metric.defaultList
    @AppStorage(TodayPrefs.chartsKey) private var chartsRaw = TodayPrefs.defaultCharts
    @AppStorage("showCheckInBanner") private var showBanner = true
    @State private var customizing = false
    private var reader = ProfileReader()

    init(day: Binding<Date>) { _day = day }

    private var kind: ChartKind {
        let k = ChartKind(rawValue: kindRaw) ?? .rings
        let vis = TodayPrefs.charts(chartsRaw)
        return vis.contains(k) ? k : vis[0]
    }
    /// Due once there is at least a week of history and 7 days have passed since the last check-in.
    private var checkInDue: Bool {
        guard Calendar.current.isDateInToday(day), let first = weights.map(\.day).min(),
              Date().timeIntervalSince(first) >= 7 * 86400 else { return false }
        return reader.lastCheckIn == 0 || Date().timeIntervalSince1970 - reader.lastCheckIn > 7 * 86400
    }

    var body: some View {
        let plan = Plan.make(weights: weights, entries: entries, profile: reader.profile, applied: reader.applied)
        let cal = Calendar.current
        let dayEntries = entries.filter { $0.day == day }
        let totals = DayTotals(dayEntries)
        let week = (0..<7).reversed().map { off -> (day: Date, totals: DayTotals) in
            let d = cal.date(byAdding: .day, value: -off, to: day)!
            return (d, DayTotals(entries.filter { $0.day == d }))
        }
        let data = ChartData(day: day, entries: dayEntries, week: week, totals: totals, targets: plan.targets, showLeft: showLeft)
        let sig = totals.calories + totals.protein * 1_000 + totals.carbs * 1_000_000 + totals.fat * 1_000_000_000 + plan.targets.calories * 7

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if checkInDue && showBanner {
                        NavigationLink { CheckInView() } label: {
                            HStack {
                                Label("Weekly check-in is ready", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }

                    chips

                    VStack(spacing: 14) {
                        Picker("Mode", selection: $showLeft) {
                            Text("Eaten").tag(false)
                            Text("Left").tag(true)
                        }.pickerStyle(.segmented)
                        chart(data)
                    }
                    .padding().background(.background, in: RoundedRectangle(cornerRadius: 20))

                    snapshot(totals, DayTotals.micros(dayEntries), plan.targets)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(dayTitle(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { DayNavToolbar(day: $day, extra: { Button { customizing = true } label: { Label("Customize Today", systemImage: "slider.horizontal.3") } }) }
        }
        .sheet(isPresented: $customizing) { CustomizeTodayView() }
        .onAppear { publish(totals, plan.targets) }
        .onChange(of: sig) { _, _ in publish(totals, plan.targets) }
    }

    private var chips: some View {
        HStack(spacing: 8) {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TodayPrefs.charts(chartsRaw)) { k in
                    Button { withAnimation(.snappy) { kindRaw = k.rawValue } } label: {
                        Label(k.title, systemImage: k.icon).font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(k == kind ? Palette.calories : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(k == kind ? .white : .primary)
                    }.buttonStyle(.plain)
                }
            }
        }
            Button { customizing = true } label: {
                Image(systemName: "slider.horizontal.3").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Customize Today")
        }
    }

    @ViewBuilder private func chart(_ d: ChartData) -> some View {
        switch kind {
        case .rings: RingsChart(d: d)
        case .bars: BarsChart(d: d)
        case .donut: DonutChart(d: d)
        case .meals: MealsChart(d: d)
        case .timeline: TimelineChart(d: d)
        case .week: WeekChart(d: d)
        case .weekMacros: WeekMacrosChart(d: d)
        case .micros: MicrosChart(d: d)
        }
    }

    /// Numbers under the chart; which ones is up to the user (Customize Today).
    private func snapshot(_ t: DayTotals, _ m: Micros, _ g: Targets) -> some View {
        let list = Metric.parse(metricsRaw)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(4, max(1, list.count))), spacing: 16) {
            ForEach(list) { stat($0, $0.eaten(t, m), $0.target(g)) }
        }
        .padding().background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay { if list.isEmpty { Text("Tap ⋯ → Customize Today to add numbers").font(.caption).foregroundStyle(.secondary) } }
    }

    private func stat(_ m: Metric, _ eaten: Double, _ target: Double) -> some View {
        let left = target - eaten
        let n = { (v: Double) in v >= 100 || m.isMacro ? "\(Int(v.rounded()))" : String(format: "%.1f", v) }
        return VStack(spacing: 3) {
            Text(m.title).font(.caption).foregroundStyle(m.color).lineLimit(1).minimumScaleFactor(0.7)
            Text(showLeft ? n(abs(left)) : n(eaten)).font(.headline.monospacedDigit())
                .foregroundStyle(showLeft && left < 0 ? .red : .primary)
            Text(showLeft ? (left >= 0 ? "left" : "over") : "of \(Int(target.rounded()))\(m.unit)").font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    /// Push today's numbers to the widget and (optionally) Apple Health.
    private func publish(_ t: DayTotals, _ g: Targets) {
        if Calendar.current.isDateInToday(day) {
            WidgetSnapshot(day: day, calories: t.calories, calTarget: g.calories, protein: t.protein, pTarget: g.protein,
                           carbs: t.carbs, cTarget: g.carbs, fat: t.fat, fTarget: g.fat).save()
        }
        if healthSync {
            let d = day
            Task { await Health.shared.syncNutrition(day: d, calories: t.calories, protein: t.protein, carbs: t.carbs, fat: t.fat) }
        }
    }
}
