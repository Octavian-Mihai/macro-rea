import SwiftUI
import SwiftData

/// Meal-by-meal food log for the selected day.
struct DiaryView: View {
    @Binding var day: Date
    @State private var addingMeal: Meal?
    @Query private var allWeights: [WeightEntry]
    @Query(sort: \FoodEntry.timestamp) private var allEntries: [FoodEntry]
    @Environment(\.modelContext) private var ctx
    private var reader = ProfileReader()

    init(day: Binding<Date>) { _day = day }

    var body: some View {
        let plan = Plan.make(weights: allWeights, entries: allEntries, profile: reader.profile, applied: reader.applied)
        NavigationStack {
            DayList(day: day, plan: plan, addingMeal: $addingMeal)
                .navigationTitle(dayTitle(day))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { DayNavToolbar(day: $day, extra: {
                    Button("Copy yesterday's food here", action: copyYesterday)
                }) }
                .overlay(alignment: .bottomTrailing) { addButton }
                .sheet(item: $addingMeal) { meal in
                    AddFoodView(title: "Add to \(meal.title)", day: day, meal: meal, allowRecipes: true) { item, q in
                        FoodLogger.log(ctx, item: item, qty: q, day: day, meal: meal)
                    }
                }
        }
    }

    /// Tap = add to the meal that fits the time of day; long-press to pick another meal.
    private var addButton: some View {
        Menu {
            ForEach(Meal.allCases) { m in Button { addingMeal = m } label: { Label(m.title, systemImage: m.icon) } }
        } label: {
            Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                .frame(width: 58, height: 58).background(Circle().fill(Palette.calories))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        } primaryAction: { addingMeal = defaultMeal }
        .padding(.trailing, 20).padding(.bottom, 12)
    }

    private var defaultMeal: Meal {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<11: .breakfast
        case 11..<16: .lunch
        case 16..<21: .dinner
        default: .snacks
        }
    }

    private func copyYesterday() {
        let y = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        for e in allEntries where e.day == y {
            ctx.insert(FoodEntry(day: day, meal: e.meal, name: e.name, servingText: e.servingText, quantity: e.quantity,
                                 calories: e.calories, protein: e.protein, carbs: e.carbs, fat: e.fat, micros: e.micros))
        }
    }
}

func dayTitle(_ day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return "Today" }
    if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
    return day.formatted(.dateTime.weekday(.abbreviated).month().day())
}

/// Shared prev / next / "today" controls for the day-based screens.
struct DayNavToolbar<Extra: View>: ToolbarContent {
    @Binding var day: Date
    @ViewBuilder var extra: () -> Extra

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                Menu {
                    Button("Today") { day = Calendar.current.startOfDay(for: .now) }
                    extra()
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
    private func shift(_ d: Int) { day = Calendar.current.date(byAdding: .day, value: d, to: day)! }
}

private struct DayList: View {
    let day: Date
    let plan: Plan
    @Binding var addingMeal: Meal?
    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var ctx
    @AppStorage("showLeft") private var showLeft = false
    @State private var templateName = ""
    @State private var templateMeal: Meal?

    init(day: Date, plan: Plan, addingMeal: Binding<Meal?>) {
        self.day = day; self.plan = plan; self._addingMeal = addingMeal
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day }, sort: \.timestamp)
    }

    private var totalKcal: Double { entries.reduce(0) { $0 + $1.calories } }

    var body: some View {
        List {
            Section { header }
            ForEach(Meal.allCases) { meal in
                let items = entries.filter { $0.meal == meal }
                let kcal = items.reduce(0) { $0 + $1.calories }
                Section {
                    ForEach(items) { e in
                        NavigationLink { EntryEditView(entry: e) } label: { EntryRow(entry: e) }
                    }
                    .onDelete { idx in idx.forEach { ctx.delete(items[$0]) } }
                    Button { addingMeal = meal } label: { Label("Add food", systemImage: "plus.circle.fill") }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label(meal.title, systemImage: meal.icon)
                            Spacer()
                            Text(kcal.kcalText + " kcal").monospacedDigit()
                            if !items.isEmpty {
                                Menu {
                                    Button("Save as template…") { templateName = meal.title; templateMeal = meal }
                                } label: { Image(systemName: "ellipsis") }
                            }
                        }
                        if !items.isEmpty {
                            Text("P \(items.reduce(0) { $0 + $1.protein }.gText) · C \(items.reduce(0) { $0 + $1.carbs }.gText) · F \(items.reduce(0) { $0 + $1.fat }.gText)"
                                 + (totalKcal > 0 ? " · \(Int((kcal / totalKcal * 100).rounded()))% of day" : ""))
                                .font(.caption2).textCase(nil)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 56) }
        .alert("Save meal as template", isPresented: Binding(get: { templateMeal != nil }, set: { if !$0 { templateMeal = nil } })) {
            TextField("Name", text: $templateName)
            Button("Save") { saveTemplate() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Compact status line; the full graphs live on the Today tab.
    private var header: some View {
        let g = plan.targets
        let p = entries.reduce(0) { $0 + $1.protein }, c = entries.reduce(0) { $0 + $1.carbs }, f = entries.reduce(0) { $0 + $1.fat }
        func v(_ eaten: Double, _ target: Double) -> String { showLeft ? "\(Int((target - eaten).rounded()))" : "\(Int(eaten.rounded()))" }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showLeft ? "\(Int((g.calories - totalKcal).rounded())) kcal left" : "\(totalKcal.kcalText) kcal eaten")
                    .font(.title3.bold().monospacedDigit())
                Spacer()
                Text("goal \(g.calories.kcalText)").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, totalKcal / max(1, g.calories))).tint(totalKcal > g.calories ? .red : Palette.calories)
            HStack {
                Text("P \(v(p, g.protein))g").foregroundStyle(Palette.protein)
                Spacer(); Text("C \(v(c, g.carbs))g").foregroundStyle(Palette.carbs)
                Spacer(); Text("F \(v(f, g.fat))g").foregroundStyle(Palette.fat)
                Spacer(); Text(showLeft ? "left" : "eaten").foregroundStyle(.secondary)
            }.font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func saveTemplate() {
        guard let meal = templateMeal, !templateName.isEmpty else { return }
        let items = entries.filter { $0.meal == meal }.map {
            RecipeItem(name: $0.name, servingText: $0.servingText, quantity: $0.quantity, calories: $0.calories,
                       protein: $0.protein, carbs: $0.carbs, fat: $0.fat, micros: $0.micros)
        }
        ctx.insert(Recipe(name: templateName, isTemplate: true, items: items))
    }
}

struct MacroBar: View {
    let name: String, value: Double, target: Double, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: min(1, value / max(1, target))).tint(color)
            Text("\(Int(value.rounded())) / \(Int(target.rounded()))g").font(.caption.monospacedDigit())
        }
    }
}

struct EntryRow: View {
    let entry: FoodEntry
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.name).lineLimit(1)
                Text("\(entry.servingText == "g" ? formatQty(entry.quantity) + " g" : formatQty(entry.quantity) + " × " + entry.servingText) · P\(Int(entry.protein.rounded())) C\(Int(entry.carbs.rounded())) F\(Int(entry.fat.rounded()))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.calories.kcalText).monospacedDigit()
        }
    }
}

func formatQty(_ q: Double) -> String {
    q == q.rounded() ? String(Int(q)) : String(format: "%.2f", q).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
}

/// Edit quantity of an existing entry (macros scale proportionally).
struct EntryEditView: View {
    @Bindable var entry: FoodEntry
    @State private var qty = ""
    var body: some View {
        Form {
            Section(entry.servingText == "g" ? "Amount (grams)" : "Servings (\(entry.servingText))") {
                TextField("Quantity", text: $qty).keyboardType(.decimalPad)
                    .onChange(of: qty) { _, new in
                        guard let n = Double(new.replacingOccurrences(of: ",", with: ".")), n > 0, entry.quantity > 0 else { return }
                        let r = n / entry.quantity
                        entry.calories *= r; entry.protein *= r; entry.carbs *= r; entry.fat *= r
                        entry.micros = entry.micros.scaled(r)
                        entry.quantity = n
                    }
            }
            Section {
                LabeledContent("Calories", value: entry.calories.kcalText)
                LabeledContent("Protein", value: entry.protein.gText)
                LabeledContent("Carbs", value: entry.carbs.gText)
                LabeledContent("Fat", value: entry.fat.gText)
            }
            MicrosSection(micros: entry.micros)
        }
        .navigationTitle(entry.name)
        .onAppear { qty = formatQty(entry.quantity) }
    }
}

struct DayMicrosView: View {
    let entries: [FoodEntry]
    var body: some View {
        let total = entries.reduce(Micros()) { $0 + $1.micros }
        List(total.rows) { r in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.name); Spacer()
                    Text(String(format: r.value < 10 ? "%.1f %@" : "%.0f %@", r.value, r.unit)).monospacedDigit()
                    Text("/ \(Int(r.daily))").foregroundStyle(.secondary).font(.caption)
                }
                ProgressView(value: min(1, r.value / r.daily)).tint(r.name == "Sodium" || r.name == "Sugar" || r.name == "Saturated fat" ? .orange : .green)
            }
        }
        .navigationTitle("Micronutrients")
        .overlay { if entries.isEmpty { Text("Nothing logged").foregroundStyle(.secondary) } }
    }
}
