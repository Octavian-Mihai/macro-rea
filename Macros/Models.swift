import Foundation
import SwiftData

enum Meal: Int, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }
    var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snacks: "carrot"
        }
    }
}


/// Optional micronutrients. g for fiber/sugar/satFat, mg for the rest.
struct Micros: Codable, Hashable {
    var fiber: Double = 0
    var sugar: Double = 0
    var satFat: Double = 0
    var sodium: Double = 0
    var potassium: Double = 0
    var calcium: Double = 0
    var iron: Double = 0
    var vitaminC: Double = 0

    func scaled(_ k: Double) -> Micros {
        Micros(fiber: fiber * k, sugar: sugar * k, satFat: satFat * k, sodium: sodium * k,
               potassium: potassium * k, calcium: calcium * k, iron: iron * k, vitaminC: vitaminC * k)
    }
    static func + (a: Micros, b: Micros) -> Micros {
        Micros(fiber: a.fiber + b.fiber, sugar: a.sugar + b.sugar, satFat: a.satFat + b.satFat,
               sodium: a.sodium + b.sodium, potassium: a.potassium + b.potassium,
               calcium: a.calcium + b.calcium, iron: a.iron + b.iron, vitaminC: a.vitaminC + b.vitaminC)
    }

    struct Row: Identifiable { var id: String { name }; var name: String; var value: Double; var unit: String; var daily: Double }
    /// Reference daily values (adult, approximate FDA DV).
    var rows: [Row] {
        [Row(name: "Fiber", value: fiber, unit: "g", daily: 28), Row(name: "Sugar", value: sugar, unit: "g", daily: 50),
         Row(name: "Saturated fat", value: satFat, unit: "g", daily: 20), Row(name: "Sodium", value: sodium, unit: "mg", daily: 2300),
         Row(name: "Potassium", value: potassium, unit: "mg", daily: 4700), Row(name: "Calcium", value: calcium, unit: "mg", daily: 1300),
         Row(name: "Iron", value: iron, unit: "mg", daily: 18), Row(name: "Vitamin C", value: vitaminC, unit: "mg", daily: 90)]
    }
}

/// One ingredient / component of a recipe or template. Values are totals for `quantity` servings.
struct RecipeItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var servingText: String
    var quantity: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var micros: Micros = Micros()
}

@Model
final class Recipe {
    var name: String
    var isTemplate: Bool        // template: logs each item separately; recipe: logs portions as one food
    var servings: Double
    var items: [RecipeItem]
    var lastUsed: Date

    init(name: String, isTemplate: Bool, servings: Double = 1, items: [RecipeItem]) {
        self.name = name; self.isTemplate = isTemplate; self.servings = servings
        self.items = items; self.lastUsed = .now
    }
    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fat } }
    var totalMicros: Micros { items.reduce(Micros()) { $0 + $1.micros } }
}

@Model
final class FoodEntry {
    var day: Date          // start of day
    var timestamp: Date
    var mealRaw: Int
    var name: String
    var servingText: String
    var quantity: Double
    var calories: Double   // totals for the entry (already multiplied by quantity)
    var protein: Double
    var carbs: Double
    var fat: Double
    var micros: Micros = Micros()

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snacks }

    init(day: Date, meal: Meal, name: String, servingText: String = "", quantity: Double = 1,
         calories: Double, protein: Double, carbs: Double, fat: Double, micros: Micros = Micros()) {
        self.micros = micros
        self.day = Calendar.current.startOfDay(for: day)
        self.timestamp = .now
        self.mealRaw = meal.rawValue
        self.name = name
        self.servingText = servingText
        self.quantity = quantity
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

/// A reusable food, nutrition is per one serving.
@Model
final class SavedFood {
    var name: String
    var brand: String
    var servingText: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var barcode: String
    var micros: Micros = Micros()
    var servingGrams: Double = 0      // >0: values are for this many grams
    var portionsJSON: String = ""
    var lastUsed: Date
    var useCount: Int

    init(name: String, brand: String = "", servingText: String = "1 serving",
         calories: Double, protein: Double, carbs: Double, fat: Double, barcode: String = "", micros: Micros = Micros()) {
        self.name = name; self.brand = brand; self.servingText = servingText
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
        self.barcode = barcode; self.micros = micros; self.lastUsed = .now; self.useCount = 0
    }
}

@Model
final class WeightEntry {
    var day: Date
    var kg: Double
    init(day: Date, kg: Double) {
        self.day = Calendar.current.startOfDay(for: day)
        self.kg = kg
    }
}

struct Portion: Hashable, Identifiable, Codable {
    var id: String { label }
    var label: String
    var grams: Double
}

/// Nutrition per 100 g, used for gram-based foods.
struct Per100: Hashable {
    var calories: Double, protein: Double, carbs: Double, fat: Double
    var micros: Micros
}

/// Lightweight, non-persisted food description used by search / scan / saved foods.
/// Gram-based foods carry `per100` + household `portions`; custom foods are serving-only.
struct FoodItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var brand: String = ""
    var servingText: String = "1 serving"
    var calories: Double      // for the current serving
    var protein: Double
    var carbs: Double
    var fat: Double
    var barcode: String = ""
    var micros: Micros = Micros()
    var per100: Per100?
    var portions: [Portion] = []   // household measures only (not "100 g"/"1 g")
    var isSaved = false

    var hasGrams: Bool { per100 != nil }

    /// Gram-based food, starting at 100 g.
    init(name: String, brand: String = "", barcode: String = "", per100: Per100, portions: [Portion]) {
        self.name = name; self.brand = brand; self.barcode = barcode
        self.per100 = per100; self.portions = portions
        self.calories = per100.calories; self.protein = per100.protein; self.carbs = per100.carbs; self.fat = per100.fat
        self.micros = per100.micros; self.servingText = "100 g"
    }

    init(name: String, brand: String = "", servingText: String = "1 serving",
         calories: Double, protein: Double, carbs: Double, fat: Double, barcode: String = "", micros: Micros = Micros()) {
        self.name = name; self.brand = brand; self.servingText = servingText
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat; self.barcode = barcode; self.micros = micros
    }

    init(_ s: SavedFood) {
        name = s.name; brand = s.brand; servingText = s.servingText
        calories = s.calories; protein = s.protein; carbs = s.carbs; fat = s.fat; barcode = s.barcode; micros = s.micros
        isSaved = true
        if s.servingGrams > 0 {
            let k = 100 / s.servingGrams
            per100 = Per100(calories: s.calories * k, protein: s.protein * k, carbs: s.carbs * k, fat: s.fat * k, micros: s.micros.scaled(k))
            if let d = s.portionsJSON.data(using: .utf8), let arr = try? JSONDecoder().decode([Portion].self, from: d) { portions = arr }
            else { portions = [] }
            if s.servingGrams != 100 && !portions.contains(where: { $0.label == s.servingText }) {
                portions.insert(Portion(label: s.servingText, grams: s.servingGrams), at: 0)
            }
        }
    }

    /// The same food expressed per one `p` (e.g. per "1 cup" or per "1 g").
    func serving(_ p: Portion) -> FoodItem {
        guard let b = per100 else { return self }
        var i = self
        let f = p.grams / 100
        i.servingText = p.label
        i.calories = b.calories * f; i.protein = b.protein * f; i.carbs = b.carbs * f; i.fat = b.fat * f
        i.micros = b.micros.scaled(f)
        return i
    }
}
