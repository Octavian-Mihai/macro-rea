import Foundation
import SwiftData

enum FoodLogger {
    /// Log a food (qty servings) and remember it in "my foods".
    static func log(_ ctx: ModelContext, item: FoodItem, qty: Double, day: Date, meal: Meal) {
        ctx.insert(FoodEntry(day: day, meal: meal, name: item.shortName, servingText: item.servingText, quantity: qty,
                             calories: item.calories * qty, protein: item.protein * qty,
                             carbs: item.carbs * qty, fat: item.fat * qty, micros: item.micros.scaled(qty)))
        remember(ctx, item)
    }

    static func remember(_ ctx: ModelContext, _ item: FoodItem) {
        // Gram-based foods are stored per 100 g so they can be re-logged in any amount.
        var item = item
        var grams = 0.0, portionsJSON = ""
        if let b = item.per100 {
            item.servingText = "100 g"
            item.calories = b.calories; item.protein = b.protein; item.carbs = b.carbs; item.fat = b.fat; item.micros = b.micros
            grams = 100
            if let d = try? JSONEncoder().encode(item.portions) { portionsJSON = String(data: d, encoding: .utf8) ?? "" }
        }
        let name = item.name, brand = item.brand, serving = item.servingText
        var d = FetchDescriptor<SavedFood>(predicate: #Predicate { $0.name == name && $0.brand == brand && $0.servingText == serving })
        d.fetchLimit = 1
        if let existing = try? ctx.fetch(d).first {
            existing.lastUsed = .now; existing.useCount += 1
        } else {
            let s = SavedFood(name: item.name, brand: item.brand, servingText: item.servingText, calories: item.calories,
                              protein: item.protein, carbs: item.carbs, fat: item.fat, barcode: item.barcode, micros: item.micros)
            s.servingGrams = grams; s.portionsJSON = portionsJSON
            s.useCount = 1
            ctx.insert(s)
        }
    }

    /// portions: for a recipe, number of its servings eaten; for a template, a multiplier on every item.
    static func logRecipe(_ ctx: ModelContext, recipe: Recipe, portions: Double, day: Date, meal: Meal) {
        recipe.lastUsed = .now
        if recipe.isTemplate {
            for i in recipe.items {
                ctx.insert(FoodEntry(day: day, meal: meal, name: i.name, servingText: i.servingText, quantity: i.quantity * portions,
                                     calories: i.calories * portions, protein: i.protein * portions, carbs: i.carbs * portions,
                                     fat: i.fat * portions, micros: i.micros.scaled(portions)))
            }
        } else {
            let k = portions / max(recipe.servings, 0.01)
            ctx.insert(FoodEntry(day: day, meal: meal, name: recipe.name, servingText: "serving", quantity: portions,
                                 calories: recipe.totalCalories * k, protein: recipe.totalProtein * k,
                                 carbs: recipe.totalCarbs * k, fat: recipe.totalFat * k, micros: recipe.totalMicros.scaled(k)))
        }
    }

    static func recipeItem(_ item: FoodItem, qty: Double) -> RecipeItem {
        RecipeItem(name: item.shortName, servingText: item.servingText, quantity: qty, calories: item.calories * qty,
                   protein: item.protein * qty, carbs: item.carbs * qty, fat: item.fat * qty, micros: item.micros.scaled(qty))
    }
}
