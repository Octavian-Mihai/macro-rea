import SwiftUI
import SwiftData

struct RecipesView: View {
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Environment(\.modelContext) private var ctx
    @State private var editing: Recipe?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(recipes) { r in
                Button { editing = r } label: {
                    VStack(alignment: .leading) {
                        Label(r.name, systemImage: r.isTemplate ? "rectangle.stack" : "book").foregroundStyle(.primary)
                        Text(r.isTemplate
                             ? "Template · \(r.items.count) items · \(r.totalCalories.kcalText) kcal"
                             : "Recipe · \(formatQty(r.servings)) servings · \((r.totalCalories / max(r.servings, 1)).kcalText) kcal each")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in idx.forEach { ctx.delete(recipes[$0]) } }
            if recipes.isEmpty { Text("No recipes or templates yet. Save a meal from the diary, or create one here.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Recipes & templates")
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { RecipeEditor(recipe: $0) }
        .sheet(isPresented: $creating) { RecipeEditor(recipe: nil) }
    }
}

struct RecipeEditor: View {
    var recipe: Recipe?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isTemplate = false
    @State private var servings = "1"
    @State private var items: [RecipeItem] = []
    @State private var adding = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $isTemplate) {
                        Text("Recipe (portions)").tag(false)
                        Text("Template (log items separately)").tag(true)
                    }
                    if !isTemplate { TextField("Servings it makes", text: $servings).keyboardType(.decimalPad) }
                }
                Section("Ingredients") {
                    ForEach(items) { i in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(i.name).lineLimit(1)
                                Text("\(formatQty(i.quantity)) × \(i.servingText)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(i.calories.kcalText).monospacedDigit()
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button { adding = true } label: { Label("Add ingredient", systemImage: "plus.circle.fill") }
                }
                Section("Totals") {
                    let cal = items.reduce(0) { $0 + $1.calories }
                    let k = isTemplate ? 1 : 1 / max(Double(servings.replacingOccurrences(of: ",", with: ".")) ?? 1, 0.01)
                    Text("\(isTemplate ? "Whole meal" : "Per serving"): \((cal * k).kcalText) kcal · P\((items.reduce(0) { $0 + $1.protein } * k).gText) C\((items.reduce(0) { $0 + $1.carbs } * k).gText) F\((items.reduce(0) { $0 + $1.fat } * k).gText)")
                        .font(.footnote)
                }
            }
            .navigationTitle(recipe == nil ? "New recipe" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.isEmpty || items.isEmpty) }
            }
            .sheet(isPresented: $adding) {
                AddFoodView(title: "Add ingredient") { item, q in items.append(FoodLogger.recipeItem(item, qty: q)) }
            }
            .onAppear {
                guard let r = recipe else { return }
                name = r.name; isTemplate = r.isTemplate; servings = formatQty(r.servings); items = r.items
            }
        }
    }

    private func save() {
        let s = max(Double(servings.replacingOccurrences(of: ",", with: ".")) ?? 1, 0.01)
        if let r = recipe { r.name = name; r.isTemplate = isTemplate; r.servings = isTemplate ? 1 : s; r.items = items }
        else { ctx.insert(Recipe(name: name, isTemplate: isTemplate, servings: isTemplate ? 1 : s, items: items)) }
        dismiss()
    }
}

struct RecipeLogView: View {
    let recipe: Recipe
    let day: Date
    let meal: Meal
    var onDone: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var text = "1"
    private var portions: Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        let k = recipe.isTemplate ? portions : portions / max(recipe.servings, 0.01)
        Form {
            Section(recipe.isTemplate ? "Multiplier" : "Servings eaten") { TextField("1", text: $text).keyboardType(.decimalPad) }
            Section("Total") {
                LabeledContent("Calories", value: (recipe.totalCalories * k).kcalText)
                LabeledContent("Protein", value: (recipe.totalProtein * k).gText)
                LabeledContent("Carbs", value: (recipe.totalCarbs * k).gText)
                LabeledContent("Fat", value: (recipe.totalFat * k).gText)
            }
            if recipe.isTemplate {
                Section("Items") { ForEach(recipe.items) { Text($0.name) } }
            }
            Button("Log") {
                FoodLogger.logRecipe(ctx, recipe: recipe, portions: portions, day: day, meal: meal)
                onDone()
            }.bold().disabled(portions <= 0)
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
