import Foundation

enum OpenFoodFacts {
    private struct SearchResponse: Decodable { var hits: [Product]? }
    private struct ProductResponse: Decodable { var product: Product?; var status: Int? }

    private struct Product: Decodable {
        var code: String?
        var product_name: String?
        var brands: Brands?
        var serving_size: String?
        var serving_quantity: Flex?
        var nutriments: [String: Flex]?
    }
    /// `brands` is a string in the product API and an array in the search API.
    private struct Brands: Decodable {
        var first: String?
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let s = try? c.decode(String.self) { first = s.components(separatedBy: ",").first }
            else if let a = try? c.decode([String].self) { first = a.first }
        }
    }
    /// OFF returns numbers as either numbers or strings.
    private struct Flex: Decodable {
        var value: Double?
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let v = try? c.decode(Double.self) { value = v }
            else if let s = try? c.decode(String.self) { value = Double(s) }
        }
    }

    static func search(_ q: String) async throws -> [FoodItem] {
        var comps = URLComponents(string: "https://search.openfoodfacts.org/search")!
        comps.queryItems = [.init(name: "q", value: q), .init(name: "page_size", value: "30"), .init(name: "langs", value: "en"),
                            .init(name: "fields", value: "code,product_name,brands,serving_size,serving_quantity,nutriments")]
        let r: SearchResponse = try await fetch(comps.url!)
        return (r.hits ?? []).compactMap(convert)
    }

    static func product(barcode: String) async throws -> FoodItem? {
        var comps = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        comps.queryItems = [.init(name: "fields", value: "code,product_name,brands,serving_size,serving_quantity,nutriments")]
        let r: ProductResponse = try await fetch(comps.url!)
        guard r.status == 1, let p = r.product else { return nil }
        return convert(p)
    }

    private static func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("PersonalMacroTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func convert(_ p: Product) -> FoodItem? {
        guard let name = p.product_name, !name.isEmpty, let n = p.nutriments,
              let kcal100 = n["energy-kcal_100g"]?.value else { return nil }
        func v(_ k: String) -> Double { n[k]?.value ?? 0 }
        let micros = Micros(fiber: v("fiber_100g"), sugar: v("sugars_100g"), satFat: v("saturated-fat_100g"),
                            sodium: v("sodium_100g") * 1000, potassium: v("potassium_100g") * 1000,
                            calcium: v("calcium_100g") * 1000, iron: v("iron_100g") * 1000,
                            vitaminC: v("vitamin-c_100g") * 1000)
        var portions: [Portion] = []
        if let g = p.serving_quantity?.value, g > 0 {
            portions.append(Portion(label: p.serving_size ?? "\(Int(g)) g", grams: g))
        }
        return FoodItem(name: name, brand: p.brands?.first ?? "", barcode: p.code ?? "",
                        per100: Per100(calories: kcal100, protein: v("proteins_100g"), carbs: v("carbohydrates_100g"),
                                       fat: v("fat_100g"), micros: micros), portions: portions)
    }
}
