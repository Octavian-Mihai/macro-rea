import SwiftUI
import SwiftData

struct SettingsView: View {
    @AppStorage(Keys.sex) private var sex = Sex.male.rawValue
    @AppStorage(Keys.age) private var age = 30
    @AppStorage(Keys.height) private var height = 178.0
    @AppStorage(Keys.activity) private var activity = Activity.light.rawValue
    @AppStorage(Keys.goalRate) private var goalRate = -0.4
    @AppStorage(Keys.proteinPerKg) private var proteinPerKg = 2.0
    @AppStorage(Keys.fatPercent) private var fatPercent = 0.27
    @AppStorage(Keys.useLbs) private var useLbs = false
    @AppStorage(Keys.healthSync) private var healthSync = false
    @AppStorage(Keys.fdcKey) private var fdcKey = ""
    @Environment(\.modelContext) private var ctx

    var body: some View {
        NavigationStack {
            Form {
                Section { NavigationLink { RecipesView() } label: { Label("Recipes & templates", systemImage: "book") } }
                Section {
                    Toggle("Sync with Apple Health", isOn: $healthSync)
                } header: { Text("Apple Health") } footer: {
                    Text("Imports your weight history and writes weight and daily calories/macros to Health.")
                }
                Section {
                    TextField("USDA API key override (optional)", text: $fdcKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Food search") } footer: {
                    Text("Adds US branded products. Normally the key comes from your .env file at build time; this field overrides it. With no key, a shared demo key is used (30 searches/hour).")
                }
                ProfileFields(sex: $sex, age: $age, height: $height, activity: $activity, goalRate: $goalRate,
                              proteinPerKg: $proteinPerKg, fatPercent: $fatPercent, useLbs: $useLbs)
            }
            .onChange(of: healthSync) { _, on in
                guard on else { return }
                Task {
                    if await Health.shared.requestAuth() { await Health.shared.importWeights(into: ctx) } else { healthSync = false }
                }
            }
                .navigationTitle("Settings")
        }
    }
}

struct ProfileFields: View {
    @Binding var sex: String
    @Binding var age: Int
    @Binding var height: Double
    @Binding var activity: Double
    @Binding var goalRate: Double
    @Binding var proteinPerKg: Double
    @Binding var fatPercent: Double
    @Binding var useLbs: Bool

    var body: some View {
        Section("About you") {
            Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) } }
            Stepper("Age: \(age)", value: $age, in: 14...90)
            Stepper("Height: \(Int(height)) cm", value: $height, in: 120...230)
            Picker("Activity", selection: $activity) { ForEach(Activity.allCases) { Text($0.title).tag($0.rawValue) } }
            Toggle("Use pounds (lb)", isOn: $useLbs)
        }
        Section {
            let shown = Units.display(goalRate, lbs: useLbs)
            Text(abs(goalRate) < 0.01 ? "Maintain" :
                 String(format: "%@ %.2f %@ / week", goalRate < 0 ? "Lose" : "Gain", abs(shown), Units.label(lbs: useLbs)))
            Slider(value: $goalRate, in: -1.0...0.5, step: 0.05)
        } header: { Text("Goal rate") } footer: { Text("Calorie target = your expenditure ± this rate (7700 kcal ≈ 1 kg).") }
        Section("Macros") {
            Stepper(String(format: "Protein: %.1f g per kg bodyweight", proteinPerKg), value: $proteinPerKg, in: 0.8...3.5, step: 0.1)
            Stepper("Fat: \(Int(fatPercent * 100))% of calories", value: $fatPercent, in: 0.15...0.45, step: 0.01)
            Text("Carbs fill the remaining calories.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct OnboardingView: View {
    @AppStorage(Keys.onboarded) private var onboarded = false
    @AppStorage(Keys.sex) private var sex = Sex.male.rawValue
    @AppStorage(Keys.age) private var age = 30
    @AppStorage(Keys.height) private var height = 178.0
    @AppStorage(Keys.activity) private var activity = Activity.light.rawValue
    @AppStorage(Keys.goalRate) private var goalRate = -0.4
    @AppStorage(Keys.proteinPerKg) private var proteinPerKg = 2.0
    @AppStorage(Keys.fatPercent) private var fatPercent = 0.27
    @AppStorage(Keys.useLbs) private var useLbs = false
    @Environment(\.modelContext) private var ctx
    @State private var weightText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Set up your profile. Your calorie target adapts automatically as you log food and weight.") }
                Section("Current weight (\(Units.label(lbs: useLbs)))") {
                    TextField("e.g. 80", text: $weightText).keyboardType(.decimalPad)
                }
                ProfileFields(sex: $sex, age: $age, height: $height, activity: $activity, goalRate: $goalRate,
                              proteinPerKg: $proteinPerKg, fatPercent: $fatPercent, useLbs: $useLbs)
                Button("Get started") {
                    if let v = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
                        ctx.insert(WeightEntry(day: .now, kg: Units.toKg(v, lbs: useLbs)))
                    }
                    onboarded = true
                }
                .bold().disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            .navigationTitle("Welcome")
        }
    }
}
