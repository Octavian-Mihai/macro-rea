import Foundation

/// USDA FoodData Central API (branded products). Uses the key from Settings, or DEMO_KEY (30 req/hour).
enum FoodDataCentral {
    private struct Response: Decodable { var foods: [Food]? }
    private struct Food: Decodable {
        var description: String?
        var brandName: String?
        var brandOwner: String?
        var gtinUpc: String?
        var servingSize: Double?
        var servingSizeUnit: String?
        var householdServingFullText: String?
        var foodNutrients: [Nutrient]?
    }
    private struct Nutrient: Decodable { var nutrientId: Int?; var value: Double? }

    static func search(_ q: String) async throws -> [FoodItem] {
        // Priority: key typed in Settings, then the .env key baked in at build time, then the shared demo key.
        let typed = (UserDefaults.standard.string(forKey: Keys.fdcKey) ?? "").trimmingCharacters(in: .whitespaces)
        let key = !typed.isEmpty ? typed : (!Secrets.fdcAPIKey.isEmpty ? Secrets.fdcAPIKey : "DEMO_KEY")
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [.init(name: "query", value: q), .init(name: "dataType", value: "Branded"),
                        .init(name: "pageSize", value: "25"), .init(name: "api_key", value: key)]
        let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: c.url!, timeoutInterval: 10))
        if (resp as? HTTPURLResponse)?.statusCode == 429 { throw URLError(.dataNotAllowed) }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return (r.foods ?? []).compactMap(convert)
    }

    private static func convert(_ f: Food) -> FoodItem? {
        guard let name = f.description, let ns = f.foodNutrients else { return nil }
        func v(_ id: Int) -> Double? { ns.first { $0.nutrientId == id }?.value }
        guard let kcal = v(1008) ?? v(2047) ?? v(2048), let protein = v(1003) else { return nil }
        let micros = Micros(fiber: v(1079) ?? 0, sugar: v(2000) ?? v(1063) ?? 0, satFat: v(1258) ?? 0, sodium: v(1093) ?? 0,
                            potassium: v(1092) ?? 0, calcium: v(1087) ?? 0, iron: v(1089) ?? 0, vitaminC: v(1162) ?? 0)
        var portions: [Portion] = []
        if let size = f.servingSize, size > 0, let unit = f.servingSizeUnit?.lowercased(), unit == "g" || unit == "ml" {
            let hh = (f.householdServingFullText ?? "").trimmingCharacters(in: .whitespaces)
            let label = hh.isEmpty ? "\(formatQty(size)) \(unit)" : "\(hh) (\(formatQty(size)) \(unit))"
            portions.append(Portion(label: label, grams: size))
        }
        let brand = (f.brandName?.isEmpty == false ? f.brandName : f.brandOwner) ?? ""
        return FoodItem(name: name.capitalizedFoodName, brand: brand.capitalizedFoodName, barcode: f.gtinUpc ?? "",
                        per100: Per100(calories: kcal, protein: protein, carbs: v(1005) ?? 0, fat: v(1004) ?? 0, micros: micros),
                        portions: portions)
    }
}

extension String {
    /// FDC branded names are ALL CAPS; make them readable.
    var capitalizedFoodName: String { self == uppercased() && count > 3 ? localizedCapitalized : self }
}

/// One scoring function for every source, so results interleave by how well the name matches.
enum SearchRank {
    static let plain = ["raw", "cooked", "meat only", "plain", "whole", "roasted", "boiled", "grilled", "unprepared", "enriched"]
    static let processed = ["breaded", "deli", "canned", "restaurant", "fast food", "frozen", "flavored", "flavor", "prepared", "sandwich",
                            "cereal", "ready-to", "imitation", "spread", "mix", "babyfood", "baby food", "dehydrated", "formulated",
                            "seasoned", "glazed", "roll,", "luncheon", "fat-free", "oven-roasted"]

    static func terms(_ q: String) -> [String] {
        q.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// nil = does not match the query (every term must start a word in name or brand).
    static func score(name: String, brand: String, terms: [String]) -> Double? {
        guard !terms.isEmpty else { return 0 }
        let n = name.lowercased(), b = brand.lowercased()
        let words = (n + " " + b).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard terms.allSatisfy({ t in words.contains { $0.hasPrefix(t) } }) else { return nil }
        let nameWords = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var s = -Double(n.count) * 0.05
        if n == terms.joined(separator: " ") { s += 30 }
        if let t = terms.first, n.hasPrefix(t) { s += 25 }
        if let first = n.split(separator: ",").first, terms.allSatisfy({ first.contains($0) }) { s += 20 }
        if terms.allSatisfy({ t in nameWords.contains(t) }) { s += 15 }
        s += Double(plain.filter { n.contains($0) }.count) * 8
        s -= Double(processed.filter { n.contains($0) }.count) * 14
        if b.isEmpty {
            let caps = name.split(separator: " ").prefix(2).filter { $0.first?.isUppercase == true }.count
            if caps >= 2 { s -= 15 } else { s += 25 }   // generic reference food
        } else if !terms.contains(where: { t in b.split(separator: " ").contains { $0.hasPrefix(t) } }) {
            s -= 25   // branded product whose brand wasn't asked for
        }
        return s
    }
}
