import Foundation

extension String {
    /// Compact display name: drops USDA filler ("broilers or fryers", "meat only"…) and joins
    /// "Chicken, breast" into "Chicken breast". "Chicken, broilers or fryers, breast, meat only, cooked, roasted"
    /// becomes "Chicken breast, cooked, roasted".
    var shortFoodName: String {
        var parts = split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let noise: Set<String> = ["broilers or fryers", "broiler or fryers", "broilers", "meat only", "boneless", "all grades",
                                  "separable lean and fat", "separable lean only", "trimmed to 0\" fat", "trimmed to 1/8\" fat",
                                  "choice", "select", "includes foods for usda's food distribution program", "commercial",
                                  "enriched", "unenriched", "without salt", "year round average", "mature seeds"]
        parts = parts.filter { !noise.contains($0.lowercased()) }
        parts = parts.map { $0.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression) }
        guard !parts.isEmpty else { return self }
        // "Chicken", "breast" -> "Chicken breast"
        if parts.count >= 2, !parts[1].contains(" ") || parts[1].split(separator: " ").count <= 1 {
            parts[0] = parts[0] + " " + parts[1].lowercased()
            parts.remove(at: 1)
        }
        // keep it to the first four pieces
        return parts.prefix(4).joined(separator: ", ")
    }
}

extension FoodItem {
    var shortName: String { name.contains(",") ? name.shortFoodName : name }
}
