import SwiftUI
import SwiftData

@main
struct MacrosApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
            .modelContainer(for: [FoodEntry.self, SavedFood.self, WeightEntry.self])
    }
}

struct RootView: View {
    @AppStorage(Keys.onboarded) private var onboarded = false

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var quickMeal: Meal?
    @Environment(\.modelContext) private var ctx
    @AppStorage(Keys.healthSync) private var healthSync = false

    var body: some View {
        TabView {
            DashboardView(day: $day).tabItem { Label("Today", systemImage: "chart.pie.fill") }
            DiaryView(day: $day).tabItem { Label("Diary", systemImage: "fork.knife") }
            WeightView().tabItem { Label("Weight", systemImage: "scalemass") }
            InsightsView().tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .overlay(alignment: .bottomTrailing) {
            if onboarded { QuickAddButton(addingMeal: $quickMeal).padding(.trailing, 16).padding(.bottom, 78) }
        }
        .sheet(item: $quickMeal) { meal in
            AddFoodView(title: "Add to \(meal.title)", day: day, meal: meal, allowRecipes: true) { item, q in
                FoodLogger.log(ctx, item: item, qty: q, day: day, meal: meal)
            }
        }
        .fullScreenCover(isPresented: .constant(!onboarded)) { OnboardingView() }
        .task { if healthSync { await Health.shared.importWeights(into: ctx) } }
    }
}

/// Shared plan computation so every screen agrees on targets.
struct Plan {
    var profile: Profile
    var expenditure: ExpenditureEstimate
    var targets: Targets
    var trendWeightKg: Double

    /// `applied` > 0 is the expenditure locked in at the last weekly check-in; 0 means follow the live estimate.
    static func make(weights: [WeightEntry], entries: [FoodEntry], profile: Profile, applied: Double = 0) -> Plan {
        let est = Engine.expenditure(weights: weights, entries: entries, profile: profile)
        let tw = Engine.trend(weights).last?.trend ?? 75
        return Plan(profile: profile, expenditure: est,
                    targets: Engine.targets(expenditure: applied > 0 ? applied : est.kcal, weightKg: tw, profile: profile),
                    trendWeightKg: tw)
    }
}

/// Reads the AppStorage profile in one place.
struct ProfileReader: DynamicProperty {
    @AppStorage(Keys.sex) var sex = Sex.male.rawValue
    @AppStorage(Keys.age) var age = 30
    @AppStorage(Keys.height) var height = 178.0
    @AppStorage(Keys.activity) var activity = Activity.light.rawValue
    @AppStorage(Keys.goalRate) var goalRate = -0.4
    @AppStorage(Keys.proteinPerKg) var proteinPerKg = 2.0
    @AppStorage(Keys.fatPercent) var fatPercent = 0.27
    @AppStorage(Keys.appliedExpenditure) var applied = 0.0
    @AppStorage(Keys.lastCheckIn) var lastCheckIn = 0.0
    @AppStorage(Keys.customProtein) var customProtein = 0.0
    @AppStorage(Keys.customCarbs) var customCarbs = 0.0
    @AppStorage(Keys.customFat) var customFat = 0.0
    @AppStorage(Keys.fiberGoal) var fiberGoal = 28.0
    var profile: Profile {
        var p = Profile.from(sex: sex, age: age, height: height, activity: activity, goalRate: goalRate,
                             proteinPerKg: proteinPerKg, fatPercent: fatPercent)
        p.customProtein = customProtein; p.customCarbs = customCarbs; p.customFat = customFat; p.fiberGoal = fiberGoal
        return p
    }
}

extension Double {
    var kcalText: String { String(Int(self.rounded())) }
    var gText: String { String(Int(self.rounded())) + "g" }
}

enum Palette {
    static let protein = Color.red
    static let carbs = Color.blue
    static let fat = Color.orange
    static let calories = Color.green
}
