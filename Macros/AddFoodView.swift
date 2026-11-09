import SwiftUI
import SwiftData

/// Food picker. One ranked list: your foods, the offline USDA database and online sources are merged by name match.
struct AddFoodView: View {
    var title: String
    var day: Date = .now
    var meal: Meal = .snacks
    var allowRecipes = false
    var onCommit: (FoodItem, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedFood.lastUsed, order: .reverse) private var saved: [SavedFood]
    @Query(sort: \Recipe.lastUsed, order: .reverse) private var recipes: [Recipe]
    @State private var query = ""
    @State private var online: [FoodItem] = []
    @State private var database: [FoodItem] = []
    @State private var searching = false
    @State private var error: String?
    @State private var scanning = false
    @State private var custom = false
    @State private var selected: FoodItem?
    @State private var selectedRecipe: Recipe?
    @State private var cache: [String: [FoodItem]] = [:]

    private var results: [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return saved.prefix(40).map { FoodItem($0) } }
        let terms = SearchRank.terms(q)
        var best: [String: (Double, FoodItem)] = [:]
        func add(_ item: FoodItem, bonus: Double) {
            guard let s = SearchRank.score(name: item.name, brand: item.brand, terms: terms) else { return }
            let key = (item.name + "|" + item.brand).lowercased()
            let total = s + bonus
            if best[key] == nil || best[key]!.0 < total { best[key] = (total, item) }
        }
        for f in saved { add(FoodItem(f), bonus: 60 + Double(min(f.useCount, 20))) }
        for f in database { add(f, bonus: 0) }
        for f in online { add(f, bonus: 0) }
        return best.values.sorted { $0.0 > $1.0 }.prefix(60).map(\.1)
    }
    private var myRecipes: [Recipe] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Array(recipes.prefix(5)) : recipes.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                if allowRecipes && !myRecipes.isEmpty {
                    Section {
                        ForEach(myRecipes) { r in
                            Button { selectedRecipe = r } label: {
                                HStack {
                                    Label(r.name, systemImage: r.isTemplate ? "rectangle.stack" : "book").foregroundStyle(.primary)
                                    Spacer()
                                    Text((r.isTemplate ? r.totalCalories : r.totalCalories / max(r.servings, 1)).kcalText)
                                        .foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(results) { r in Button { selected = r } label: { FoodRow(item: r) } }
                    if results.isEmpty && !searching { Text(query.isEmpty ? "Search for a food, or scan a barcode." : "No matches yet").foregroundStyle(.secondary) }
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .onChange(of: query) { _, q in
                database = q.trimmingCharacters(in: .whitespaces).count >= 2 ? FoodDB.shared.search(q) : []
            }
            .task(id: query) { await searchOnline() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                    Button { custom = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .navigationDestination(item: $selected) { item in
                FoodDetailView(item: item) { i, q in onCommit(i, q); dismiss() }
            }
            .navigationDestination(item: $selectedRecipe) { r in
                RecipeLogView(recipe: r, day: day, meal: meal) { dismiss() }
            }
            .navigationDestination(isPresented: $custom) {
                CustomFoodView { i, q in onCommit(i, q); dismiss() }
            }
            .sheet(isPresented: $scanning) {
                ScannerSheet { code in
                    scanning = false
                    Task { await lookup(barcode: code) }
                }
            }
        }
    }

    /// Debounced search-as-you-type against the online sources (run in parallel; either may fail).
    private func searchOnline() async {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 3 else { online = []; error = nil; return }
        if let hit = cache[q] { online = hit; return }
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }
        searching = true; error = nil
        defer { searching = false }
        async let off = try? OpenFoodFacts.search(q)
        async let fdc = try? FoodDataCentral.search(q)
        let (a, b) = await (off, fdc)
        if Task.isCancelled { return }
        if a == nil && b == nil { error = "Online search unavailable. Showing offline results." }
        let items = (a ?? []) + (b ?? [])
        cache[q] = items
        online = items
    }

    private func lookup(barcode: String) async {
        if let s = saved.first(where: { $0.barcode == barcode }) { selected = FoodItem(s); return }
        searching = true; error = nil
        defer { searching = false }
        do {
            if let item = try await OpenFoodFacts.product(barcode: barcode) { selected = item }
            else { error = "Barcode \(barcode) not found." }
        } catch { self.error = "Lookup failed: \(error.localizedDescription)" }
    }
}

struct FoodRow: View {
    let item: FoodItem
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.shortName).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                if !item.brand.isEmpty { Text(item.brand).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((item.per100?.calories ?? item.calories).kcalText).foregroundStyle(.primary).monospacedDigit()
                Text(item.hasGrams ? "kcal / 100 g" : "kcal / \(item.servingText)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Amount entry: grams by default, or household servings.
struct FoodDetailView: View {
    let base: FoodItem
    var onCommit: (FoodItem, Double) -> Void
    @State private var unit = "g"
    @State private var qtyText = "100"

    init(item: FoodItem, onCommit: @escaping (FoodItem, Double) -> Void) {
        self.base = item; self.onCommit = onCommit
        _unit = State(initialValue: item.hasGrams ? "g" : item.servingText)
        _qtyText = State(initialValue: item.hasGrams ? "100" : "1")
    }

    private var qty: Double { Double(qtyText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    /// The food expressed per one selected unit, and how many units.
    private var unitItem: FoodItem {
        if base.hasGrams {
            if unit == "g" { return base.serving(Portion(label: "g", grams: 1)) }
            if let p = base.portions.first(where: { $0.label == unit }) { return base.serving(p) }
        }
        return base
    }

    var body: some View {
        let it = unitItem
        Form {
            if base.shortName != base.name { Section { Text(base.name).font(.footnote).foregroundStyle(.secondary) } }
            Section {
                if base.hasGrams {
                    Picker("Unit", selection: $unit) {
                        Text("grams").tag("g")
                        ForEach(base.portions) { Text($0.label).tag($0.label) }
                    }
                } else {
                    LabeledContent("Serving", value: base.servingText)
                }
                HStack {
                    TextField(unit == "g" ? "Grams" : "Quantity", text: $qtyText).keyboardType(.decimalPad)
                    if unit == "g" { Text("g").foregroundStyle(.secondary) }
                }
            } header: { Text(base.brand.isEmpty ? "Amount" : "Amount · \(base.brand)") }
            Section("Total") {
                LabeledContent("Calories", value: (it.calories * qty).kcalText)
                LabeledContent("Protein", value: (it.protein * qty).gText)
                LabeledContent("Carbs", value: (it.carbs * qty).gText)
                LabeledContent("Fat", value: (it.fat * qty).gText)
            }
            MicrosSection(micros: it.micros.scaled(qty))
            Button("Add") { onCommit(it, qty) }.disabled(qty <= 0).bold()
        }
        .onChange(of: unit) { _, u in qtyText = u == "g" ? "100" : "1" }
        .navigationTitle(base.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomFoodView: View {
    var onCommit: (FoodItem, Double) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var servingGrams = ""
    @State private var cal = ""
    @State private var p = ""
    @State private var c = ""
    @State private var f = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var sodium = ""
    @State private var saveIt = true

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var calories: Double { cal.isEmpty ? num(p) * 4 + num(c) * 4 + num(f) * 9 : num(cal) }

    var body: some View {
        Form {
            Section {
                TextField("Name (e.g. Quick add)", text: $name)
                TextField("Serving label", text: $serving)
                field("Serving weight in grams (optional)", $servingGrams)
            } footer: { Text("Add the weight to log this food in grams later.") }
            Section("Nutrition per serving") {
                field("Calories (auto from macros if empty)", $cal)
                field("Protein (g)", $p); field("Carbs (g)", $c); field("Fat (g)", $f)
            }
            Section("Optional") {
                field("Fiber (g)", $fiber); field("Sugar (g)", $sugar); field("Sodium (mg)", $sodium)
            }
            Toggle("Save to my foods", isOn: $saveIt)
            Button("Add") {
                let n = name.isEmpty ? "Quick add" : name
                let micros = Micros(fiber: num(fiber), sugar: num(sugar), sodium: num(sodium))
                var item = FoodItem(name: n, servingText: serving, calories: calories, protein: num(p), carbs: num(c), fat: num(f), micros: micros)
                let g = num(servingGrams)
                if g > 0 {
                    let k = 100 / g
                    item = FoodItem(name: n, per100: Per100(calories: calories * k, protein: num(p) * k, carbs: num(c) * k, fat: num(f) * k,
                                                            micros: micros.scaled(k)), portions: [Portion(label: serving, grams: g)])
                }
                if saveIt && !name.isEmpty { FoodLogger.remember(ctx, item) }
                onCommit(g > 0 ? item.serving(Portion(label: serving, grams: g)) : item, 1)
            }.bold().disabled(calories <= 0)
        }
        .navigationTitle("Custom food")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, _ b: Binding<String>) -> some View {
        TextField(title, text: b).keyboardType(.decimalPad)
    }
}

struct MicrosSection: View {
    let micros: Micros
    var body: some View {
        let rows = micros.rows.filter { $0.value > 0 }
        if !rows.isEmpty {
            Section("Micronutrients") {
                ForEach(rows) { r in
                    LabeledContent(r.name, value: String(format: r.value < 10 ? "%.1f %@" : "%.0f %@", r.value, r.unit))
                }
            }
        }
    }
}
