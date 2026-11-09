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
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                if DemoData.available {
                    Section {
                        Button("Load demo data") { DemoData.load(into: ctx) }
                    } header: { Text("Demo (local build only)") }
                }
                AppearanceSection()
                Section { NavigationLink { RecipesView() } label: { Label("Recipes & templates", systemImage: "book") } }
                Section {
                    Toggle("Sync with Apple Health", isOn: $healthSync)
                } header: { Text("Apple Health") } footer: {
                    Text("Imports your weight history and writes weight and daily calories/macros to Health.")
                }
                Section {
                    TextField("USDA API key (optional)", text: $fdcKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Food search") } footer: {
                    Text("Adds US branded products to search. Optional: paste your own free USDA FoodData Central key to raise the daily search limit.")
                }
                ProfileFields(sex: $sex, age: $age, height: $height, activity: $activity, goalRate: $goalRate,
                              proteinPerKg: $proteinPerKg, fatPercent: $fatPercent, useLbs: $useLbs)
                GoalFields()
                Section { Button("Erase all logged data", role: .destructive) { confirmClear = true } }
            }
            .onChange(of: healthSync) { _, on in
                guard on else { return }
                Task {
                    if await Health.shared.requestAuth() { await Health.shared.importWeights(into: ctx) } else { healthSync = false }
                }
            }
                .keyboardDoneButton()
            .navigationTitle("Settings")
                .alert("Erase all logged food and weight?", isPresented: $confirmClear) {
                    Button("Erase", role: .destructive) { DemoData.clear(from: ctx) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This can't be undone.") }
        }
    }
}

/// Type a whole number from the keyboard. Valid values apply as you type; leaving the field snaps it into range.
extension View {
    /// One "Done" button above the keyboard (number pads have no return key).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
    }
}

struct NumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                .focused($focused)
                .onChange(of: text) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(3))
                    if digits != new { text = digits }
                    if let v = Double(digits), range.contains(v) { value = v }
                }
                .onChange(of: focused) { _, on in if !on { snap() } }
            Text(unit).foregroundStyle(.secondary)
        }
        .onAppear { text = String(Int(value.rounded())) }
    }

    private func snap() {
        let v = min(max(Double(text) ?? value, range.lowerBound), range.upperBound)
        value = v
        text = String(Int(v.rounded()))
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
        AboutYouSection(sex: $sex, age: $age, height: $height, activity: $activity, useLbs: $useLbs)
        GoalRateSection(goalRate: $goalRate, useLbs: useLbs)
        MacroSection(proteinPerKg: $proteinPerKg, fatPercent: $fatPercent)
    }
}

struct AboutYouSection: View {
    @Binding var sex: String
    @Binding var age: Int
    @Binding var height: Double
    @Binding var activity: Double
    @Binding var useLbs: Bool
    var body: some View {
        Section("About you") {
            Picker("Sex", selection: $sex) { ForEach(Sex.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) } }
            NumberField(title: "Age", unit: "years", value: Binding(get: { Double(age) }, set: { age = Int($0) }), range: 14...90)
            NumberField(title: "Height", unit: "cm", value: $height, range: 120...230)
            Picker("Activity", selection: $activity) { ForEach(Activity.allCases) { Text($0.title).tag($0.rawValue) } }
            Toggle("Use pounds (lb)", isOn: $useLbs)
        }
    }
}

struct GoalRateSection: View {
    @Binding var goalRate: Double
    let useLbs: Bool
    var body: some View {
        Section {
            let shown = Units.display(goalRate, lbs: useLbs)
            Text(abs(goalRate) < 0.01 ? "Maintain" :
                 String(format: "%@ %.2f %@ / week", goalRate < 0 ? "Lose" : "Gain", abs(shown), Units.label(lbs: useLbs)))
            Slider(value: $goalRate, in: -1.0...0.5, step: 0.05)
        } header: { Text("Goal rate") } footer: { Text("Your calorie target is your daily energy use adjusted by this weekly rate.") }
    }
}

struct MacroSection: View {
    @Binding var proteinPerKg: Double
    @Binding var fatPercent: Double
    var body: some View {
        Section("Macros") {
            Stepper(String(format: "Protein: %.1f g per kg bodyweight", proteinPerKg), value: $proteinPerKg, in: 0.8...3.5, step: 0.1)
            Stepper("Fat: \(Int(fatPercent * 100))% of calories", value: $fatPercent, in: 0.15...0.45, step: 0.01)
            Text("Carbs fill the remaining calories.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Optional fixed goals. Empty / 0 = automatic from your profile; calories always adapt on their own.
struct GoalFields: View {
    @AppStorage(Keys.customProtein) private var protein = 0.0
    @AppStorage(Keys.customCarbs) private var carbs = 0.0
    @AppStorage(Keys.customFat) private var fat = 0.0
    @AppStorage(Keys.fiberGoal) private var fiber = 28.0

    var body: some View {
        Section {
            row("Protein", $protein, "g")
            row("Carbs", $carbs, "g")
            row("Fat", $fat, "g")
            row("Fiber", $fiber, "g", auto: false)
        } header: { Text("Daily goals") } footer: {
            Text("Set your own protein, carbs and fat in grams. Leave a field empty to keep it automatic (from the settings above). Calories always follow your adaptive target.")
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ unit: String, auto: Bool = true) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(auto ? "Auto" : "28", text: Binding(
                get: { value.wrappedValue > 0 ? String(Int(value.wrappedValue.rounded())) : "" },
                set: { value.wrappedValue = Double(String($0.filter(\.isNumber).prefix(3))) ?? 0 }))
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).foregroundStyle(.secondary)
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
    @State private var step = 0

    private var weightOK: Bool { Double(weightText.replacingOccurrences(of: ",", with: ".")) != nil }

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case 0:
                    Section { Text("A few quick questions. Your calorie target then adapts automatically as you log food and weight.") }
                    Section("Current weight (\(Units.label(lbs: useLbs)))") {
                        TextField("e.g. 80", text: $weightText).keyboardType(.decimalPad)
                    }
                    AboutYouSection(sex: $sex, age: $age, height: $height, activity: $activity, useLbs: $useLbs)
                case 1:
                    GoalRateSection(goalRate: $goalRate, useLbs: useLbs)
                default:
                    MacroSection(proteinPerKg: $proteinPerKg, fatPercent: $fatPercent)
                    Section { Text("You can change any of this later in Settings.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(["About you", "Your goal", "Your targets"][step])
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Text("Step \(step + 1) of 3").font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        if step > 0 { Button("Back") { withAnimation { step -= 1 } }.buttonStyle(.bordered).controlSize(.large) }
                        Button(step < 2 ? "Continue" : "Get started") { advance() }
                            .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                            .disabled(step == 0 && !weightOK)
                    }
                }
                .padding().background(.bar)
            }
        }
    }

    private func advance() {
        if step < 2 { withAnimation { step += 1 }; return }
        if let v = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
            ctx.insert(WeightEntry(day: .now, kg: Units.toKg(v, lbs: useLbs)))
        }
        onboarded = true
    }
}

/// Colour theme and light/dark preference.
struct AppearanceSection: View {
    @AppStorage(Theme.storageKey, store: Theme.store) private var themeID = "classic"
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Section {
            ForEach(Theme.all) { t in
                Button {
                    themeID = t.id
                    Theme.select(t.id)
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -6) {
                            ForEach([t.calories, t.protein, t.carbs, t.fat], id: \.self) { c in
                                Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().stroke(.background, lineWidth: 2))
                            }
                        }
                        Text(t.name).foregroundStyle(.primary)
                        Spacer()
                        if t.id == themeID { Image(systemName: "checkmark").foregroundStyle(t.accent).fontWeight(.semibold) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t.id == themeID ? .isSelected : [])
            }
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        } header: { Text("Theme") } footer: {
            Text("Colours for calories, protein, carbs and fat. High contrast uses deeper tones that are easier to tell apart.")
        }
    }
}
