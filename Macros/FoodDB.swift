import Foundation
import SQLite3

/// Offline USDA SR Legacy database (bundled `foods.sqlite`, SQLite + FTS5).
final class FoodDB {
    static let shared = FoodDB()
    private var db: OpaquePointer?

    private init() {
        guard let path = Bundle.main.path(forResource: "foods", ofType: "sqlite") else { return }
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK { db = nil }
    }

    func search(_ query: String) -> [FoodItem] {
        guard let db else { return [] }
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"*" }.joined(separator: " ")
        let sql = """
        SELECT f.name, f.kcal, f.protein, f.carbs, f.fat, f.fiber, f.sugar, f.satfat, f.sodium, f.potassium,
               f.calcium, f.iron, f.vitc, f.portions, f.id
        FROM foods_fts JOIN foods f ON f.id = foods_fts.rowid
        WHERE foods_fts MATCH ? ORDER BY bm25(foods_fts) LIMIT 120
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var out: [FoodItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            func d(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
            let micros = Micros(fiber: d(5), sugar: d(6), satFat: d(7), sodium: d(8), potassium: d(9),
                                calcium: d(10), iron: d(11), vitaminC: d(12))
            var portions: [Portion] = []
            if let c = sqlite3_column_text(stmt, 13), let data = String(cString: c).data(using: .utf8),
               let arr = try? JSONDecoder().decode([[PortionValue]].self, from: data) {
                for p in arr where p.count == 2 { if case .s(let l) = p[0], case .n(let g) = p[1], !l.isEmpty { portions.append(Portion(label: l, grams: g)) } }
            }
            out.append(FoodItem(name: name, per100: Per100(calories: d(1), protein: d(2), carbs: d(3), fat: d(4), micros: micros), portions: portions))
        }
        return out
    }

    private enum PortionValue: Decodable {
        case s(String), n(Double)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let v = try? c.decode(Double.self) { self = .n(v) } else { self = .s(try c.decode(String.self)) }
        }
    }
}
