import Foundation

struct Targets {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double = 28
}

struct ExpenditureEstimate {
    var kcal: Double
    var formulaKcal: Double
    var confidence: Double   // 0...1, how much the estimate is driven by your own data
    var loggedDays: Int
}

enum Engine {
    static let kcalPerKg = 7700.0
    static var cal: Calendar { Calendar.current }

    /// Exponentially smoothed weight trend, one value per day from first weigh-in to `through`.
    static func trend(_ weights: [WeightEntry], through end: Date = .now) -> [(day: Date, trend: Double, raw: Double?)] {
        let sorted = weights.sorted { $0.day < $1.day }
        guard let first = sorted.first else { return [] }
        var byDay: [Date: Double] = [:]
        for w in sorted { byDay[w.day] = w.kg }
        var out: [(Date, Double, Double?)] = []
        var t = first.kg
        var d = first.day
        let last = max(cal.startOfDay(for: end), sorted.last!.day)
        var seeded = false
        while d <= last {
            if let w = byDay[d] {
                t = seeded ? t + 0.1 * (w - t) : w
                seeded = true
                out.append((d, t, w))
            } else {
                out.append((d, t, nil))
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    static func bmr(_ p: Profile, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return base + (p.sex == .male ? 5 : -161)
    }

    /// Adaptive expenditure: blends a formula estimate with what your intake and weight trend imply.
    static func expenditure(weights: [WeightEntry], entries: [FoodEntry], profile: Profile) -> ExpenditureEstimate {
        let tr = trend(weights)
        let currentWeight = tr.last?.trend ?? 75
        let formula = bmr(profile, weightKg: currentWeight) * profile.activity.rawValue

        var intakeByDay: [Date: Double] = [:]
        for e in entries { intakeByDay[e.day, default: 0] += e.calories }

        let today = cal.startOfDay(for: .now)
        let windowStart = cal.date(byAdding: .day, value: -28, to: today)!
        let loggedDays = intakeByDay.filter { $0.key >= windowStart && $0.key < today && $0.value >= 800 }
        guard loggedDays.count >= 7,
              let startPt = tr.first(where: { $0.day >= windowStart }),
              let endPt = tr.last(where: { $0.day < today }) ?? tr.last
        else { return .init(kcal: formula, formulaKcal: formula, confidence: 0, loggedDays: loggedDays.count) }

        let span = cal.dateComponents([.day], from: startPt.day, to: endPt.day).day ?? 0
        guard span >= 7 else { return .init(kcal: formula, formulaKcal: formula, confidence: 0, loggedDays: loggedDays.count) }

        let avgIntake = loggedDays.values.reduce(0, +) / Double(loggedDays.count)
        let dailyChangeKg = (endPt.trend - startPt.trend) / Double(span)
        let fromData = avgIntake - dailyChangeKg * kcalPerKg
        let conf = min(1, Double(loggedDays.count) / 21) * min(1, Double(span) / 14)
        let blended = min(6000, max(1000, formula * (1 - conf) + fromData * conf))
        return .init(kcal: blended, formulaKcal: formula, confidence: conf, loggedDays: loggedDays.count)
    }

    static func targets(expenditure: Double, weightKg: Double, profile: Profile) -> Targets {
        let adjust = profile.goalRateKgPerWeek * kcalPerKg / 7
        let floorKcal = profile.sex == .male ? 1500.0 : 1200.0
        let kcal = max(floorKcal, expenditure + adjust).rounded()
        // A custom (> 0) value wins; anything left on "auto" is derived from the calorie target.
        let protein = profile.customProtein > 0 ? profile.customProtein : (profile.proteinPerKg * weightKg).rounded()
        let fat = profile.customFat > 0 ? profile.customFat : (kcal * profile.fatPercent / 9).rounded()
        let carbs = profile.customCarbs > 0 ? profile.customCarbs : max(0, ((kcal - protein * 4 - fat * 9) / 4)).rounded()
        return Targets(calories: kcal, protein: protein, carbs: carbs, fat: fat, fiber: profile.fiberGoal)
    }

    /// Weekly change of the trend weight in kg (last 7 days), if available.
    static func weeklyChange(_ weights: [WeightEntry]) -> Double? {
        let tr = trend(weights)
        guard let last = tr.last, tr.count > 7 else { return nil }
        return last.trend - tr[tr.count - 8].trend
    }
}
