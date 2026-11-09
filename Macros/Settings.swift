import SwiftUI

enum Sex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
}

enum Activity: Double, CaseIterable, Identifiable {
    case sedentary = 1.2, light = 1.375, moderate = 1.55, high = 1.725
    var id: Double { rawValue }
    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .high: "Very active"
        }
    }
}

/// User profile + preferences, backed by AppStorage keys.
struct Profile {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var activity: Activity
    var goalRateKgPerWeek: Double   // negative = lose
    var proteinPerKg: Double
    var fatPercent: Double          // share of calories
    var customProtein = 0.0         // grams; 0 = automatic
    var customCarbs = 0.0
    var customFat = 0.0
    var fiberGoal = 28.0
}

enum Keys {
    static let onboarded = "onboarded"
    static let sex = "sex"
    static let age = "age"
    static let height = "heightCm"
    static let activity = "activity"
    static let goalRate = "goalRate"
    static let proteinPerKg = "proteinPerKg"
    static let fatPercent = "fatPercent"
    static let useLbs = "useLbs"
    static let appliedExpenditure = "appliedExpenditure"
    static let lastCheckIn = "lastCheckIn"
    static let healthSync = "healthSync"
    static let fdcKey = "fdcKey"
    static let customProtein = "customProtein"
    static let customCarbs = "customCarbs"
    static let customFat = "customFat"
    static let fiberGoal = "fiberGoal"
}

extension Profile {
    static func from(sex: String, age: Int, height: Double, activity: Double, goalRate: Double,
                     proteinPerKg: Double, fatPercent: Double) -> Profile {
        Profile(sex: Sex(rawValue: sex) ?? .male, age: age, heightCm: height,
                activity: Activity(rawValue: activity) ?? .light,
                goalRateKgPerWeek: goalRate, proteinPerKg: proteinPerKg, fatPercent: fatPercent)
    }
}

enum Units {
    static let kgPerLb = 0.45359237
    static func display(_ kg: Double, lbs: Bool) -> Double { lbs ? kg / kgPerLb : kg }
    static func toKg(_ v: Double, lbs: Bool) -> Double { lbs ? v * kgPerLb : v }
    static func label(lbs: Bool) -> String { lbs ? "lb" : "kg" }
}
