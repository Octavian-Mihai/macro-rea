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
    @State private var restored = false

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
            .onAppear(perform: restoreDraft)
            .onChange(of: query) { _, q in
                database = q.trimmingCharacters(in: .whitespaces).count >= 2 ? FoodDB.shared.search(q) : []
                saveDraft()
            }
            .onChange(of: selected) { _, _ in saveDraft() }
            .onChange(of: custom) { _, _ in saveDraft() }
            .task(id: query) { await searchOnline() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { AddDraft.clear(); dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                    Button { custom = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .navigationDestination(item: $selected) { item in
                FoodDetailView(item: item) { i, q in onCommit(i, q); AddDraft.clear(); dismiss() }
            }
            .navigationDestination(item: $selectedRecipe) { r in
                RecipeLogView(recipe: r, day: day, meal: meal) { AddDraft.clear(); dismiss() }
            }
            .navigationDestination(isPresented: $custom) {
                CustomFoodView { i, q in onCommit(i, q); AddDraft.clear(); dismiss() }
            }
            .sheet(isPresented: $scanning) {
                ScannerSheet { code in
                    scanning = false
                    Task { await lookup(barcode: code) }
                }
            }
        }
    }

    private func saveDraft() {
        guard restored else { return }
        AddDraft.update {
            $0.meal = meal.rawValue; $0.day = day; $0.query = query; $0.selected = selected; $0.customOpen = custom
            if selected == nil { $0.qtyText = nil; $0.unit = nil }
        }
    }

    /// Pick up where the user left off if the app was closed mid-entry.
    private func restoreDraft() {
        guard !restored else { return }
        if let d = AddDraft.load() {
            query = d.query
            selected = d.selected
            custom = d.customOpen
        }
        restored = true
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
        // Resume the amount typed before the app was closed (same food only).
        let d = AddDraft.load().flatMap { $0.selected?.id == item.id ? $0 : nil }
        _unit = State(initialValue: d?.unit ?? (item.hasGrams ? "g" : item.servingText))
        _qtyText = State(initialValue: d?.qtyText ?? (item.hasGrams ? "100" : "1"))
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
        .onChange(of: unit) { _, u in
            qtyText = u == "g" ? "100" : "1"
            AddDraft.update { $0.unit = u; $0.qtyText = qtyText }
        }
        .onChange(of: qtyText) { _, q in AddDraft.update { $0.qtyText = q; $0.unit = unit } }
        .navigationTitle(base.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomFoodView: View {
    var onCommit: (FoodItem, Double) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var name: String
    @State private var serving: String
    @State private var servingGrams: String
    @State private var cal: String
    @State private var p: String
    @State private var c: String
    @State private var f: String
    @State private var fiber: String
    @State private var sugar: String
    @State private var sodium: String
    @State private var saveIt: Bool

    init(onCommit: @escaping (FoodItem, Double) -> Void) {
        self.onCommit = onCommit
        let d = AddDraft.load()?.customFields ?? [:]
        _name = State(initialValue: d["name"] ?? "")
        _serving = State(initialValue: d["serving"] ?? "1 serving")
        _servingGrams = State(initialValue: d["servingGrams"] ?? "")
        _cal = State(initialValue: d["cal"] ?? "")
        _p = State(initialValue: d["p"] ?? "")
        _c = State(initialValue: d["c"] ?? "")
        _f = State(initialValue: d["f"] ?? "")
        _fiber = State(initialValue: d["fiber"] ?? "")
        _sugar = State(initialValue: d["sugar"] ?? "")
        _sodium = State(initialValue: d["sodium"] ?? "")
        _saveIt = State(initialValue: d["saveIt"].map { $0 == "1" } ?? true)
    }

    /// Everything typed so far, mirrored into the saved draft.
    private var fields: [String: String] {
        ["name": name, "serving": serving, "servingGrams": servingGrams, "cal": cal, "p": p, "c": c, "f": f,
         "fiber": fiber, "sugar": sugar, "sodium": sodium, "saveIt": saveIt ? "1" : "0"]
    }

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
        .onChange(of: fields) { _, f in AddDraft.update { $0.customFields = f } }
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
