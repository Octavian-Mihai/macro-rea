import Foundation
import HealthKit
import SwiftData

@MainActor
final class Health {
    static let shared = Health()
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private let mass = HKQuantityType(.bodyMass)
    private var nutrition: [(HKQuantityType, HKUnit)] {
        [(HKQuantityType(.dietaryEnergyConsumed), .kilocalorie()), (HKQuantityType(.dietaryProtein), .gram()),
         (HKQuantityType(.dietaryCarbohydrates), .gram()), (HKQuantityType(.dietaryFatTotal), .gram())]
    }

    func requestAuth() async -> Bool {
        guard available else { return false }
        let share: Set<HKSampleType> = Set([mass] + nutrition.map(\.0))
        do { try await store.requestAuthorization(toShare: share, read: [mass]); return true } catch { return false }
    }

    /// Import body-mass samples (latest per day); never overwrites weights you logged by hand.
    func importWeights(into ctx: ModelContext, days: Int = 365) async {
        guard available else { return }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let pred = HKQuery.predicateForSamples(withStart: start, end: nil)
        let desc = HKSampleQueryDescriptor(predicates: [.quantitySample(type: mass, predicate: pred)],
                                           sortDescriptors: [SortDescriptor(\.endDate)], limit: nil)
        guard let samples = try? await desc.result(for: store) else { return }
        var latest: [Date: Double] = [:]
        for s in samples { latest[Calendar.current.startOfDay(for: s.endDate)] = s.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
        let existing = Set(((try? ctx.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.day))
        for (d, kg) in latest where !existing.contains(d) { ctx.insert(WeightEntry(day: d, kg: kg)) }
    }

    func saveWeight(kg: Double, date: Date) async {
        guard available else { return }
        let s = HKQuantitySample(type: mass, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), start: date, end: date)
        try? await store.save(s)
    }

    /// One sample per nutrient per day, replaced in place via sync identifiers.
    func syncNutrition(day: Date, calories: Double, protein: Double, carbs: Double, fat: Double) async {
        guard available else { return }
        let values = [calories, protein, carbs, fat]
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let stamp = df.string(from: day)
        let when = Calendar.current.date(byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: day))!
        let version = Int(Date().timeIntervalSince1970)
        var samples: [HKQuantitySample] = []
        for (i, (type, unit)) in nutrition.enumerated() {
            let meta: [String: Any] = [HKMetadataKeySyncIdentifier: "macros.\(type.identifier).\(stamp)", HKMetadataKeySyncVersion: version]
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: values[i]), start: when, end: when, metadata: meta))
        }
        try? await store.save(samples)
    }
}
