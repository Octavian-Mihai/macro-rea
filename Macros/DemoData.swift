import Foundation
import SwiftData

/// Hooks for developer-only sample data. The generator lives in `DemoData.local.swift`, which is not
/// committed; builds without it (everyone else) get a no-op and no Demo section in Settings.
enum DemoData {
    #if LOCAL_DEMO
    static let available = true
    #else
    static let available = false
    static func load(into ctx: ModelContext, days: Int = 35) {}
    #endif

    static func clear(from ctx: ModelContext) {
        try? ctx.delete(model: FoodEntry.self)
        try? ctx.delete(model: WeightEntry.self)
        try? ctx.save()
    }
}
