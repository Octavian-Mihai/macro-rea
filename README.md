# Macros

A personal macro and calorie tracker for iPhone (SwiftUI, SwiftData, Swift Charts, WidgetKit, HealthKit).

## Build

```bash
brew install xcodegen
cp .env.example .env        # optional: add your USDA FoodData Central key (FDC_API_KEY=...)
xcodegen generate
open Macros.xcodeproj
```

The Xcode project is generated from `project.yml`, so it is not committed. `.env` is git-ignored and is
copied into the app bundle at build time. Without a key the app falls back to USDA's shared demo key.

## Data sources

Offline USDA SR Legacy (bundled `Macros/foods.sqlite`, rebuild with `tools/build_food_db.py`),
Open Food Facts and USDA FoodData Central (online), merged into a single ranked search.
