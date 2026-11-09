#!/usr/bin/env python3
"""Builds Macros/foods.sqlite (SQLite + FTS5) from the USDA FoodData Central SR Legacy CSV export.
usage: build_food_db.py <sr_legacy_csv_dir> <out.sqlite>"""
import csv, json, os, sqlite3, sys

src, out = sys.argv[1], sys.argv[2]
NUT = {1008: "kcal", 1003: "protein", 1005: "carbs", 1004: "fat", 1079: "fiber", 2000: "sugar", 1063: "sugar",
       1258: "satfat", 1093: "sodium", 1092: "potassium", 1087: "calcium", 1089: "iron", 1162: "vitc"}
def rows(name):
    with open(os.path.join(src, name), newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)

foods = {r["fdc_id"]: r["description"] for r in rows("food.csv") if r["data_type"] == "sr_legacy_food"}
vals = {i: {} for i in foods}
for r in rows("food_nutrient.csv"):
    k = NUT.get(int(r["nutrient_id"]))
    if k and r["fdc_id"] in foods and r["amount"]:
        vals[r["fdc_id"]].setdefault(k, float(r["amount"]))
units = {r["id"]: r["name"] for r in rows("measure_unit.csv")}
portions = {i: [] for i in foods}
for r in rows("food_portion.csv"):
    if r["fdc_id"] not in foods or not r["gram_weight"]:
        continue
    unit = units.get(r["measure_unit_id"], "")
    desc = " ".join(x for x in [r["amount"], "" if unit in ("undetermined", "") else unit, r["portion_description"], r["modifier"]] if x).strip()
    portions[r["fdc_id"]].append([desc or "serving", round(float(r["gram_weight"]) / (float(r["amount"]) or 1) * (float(r["amount"]) or 1), 1)])

if os.path.exists(out): os.remove(out)
db = sqlite3.connect(out)
db.execute("CREATE TABLE foods(id INTEGER PRIMARY KEY, name TEXT, kcal REAL, protein REAL, carbs REAL, fat REAL, fiber REAL, sugar REAL, satfat REAL, sodium REAL, potassium REAL, calcium REAL, iron REAL, vitc REAL, portions TEXT)")
db.execute("CREATE VIRTUAL TABLE foods_fts USING fts5(name, content='foods', content_rowid='id', tokenize='unicode61 remove_diacritics 2', prefix='2 3')")
n = 0
for i, name in foods.items():
    v = vals[i]
    if "kcal" not in v: continue
    db.execute("INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
               (int(i), name, v["kcal"], v.get("protein", 0), v.get("carbs", 0), v.get("fat", 0), v.get("fiber", 0), v.get("sugar", 0),
                v.get("satfat", 0), v.get("sodium", 0), v.get("potassium", 0), v.get("calcium", 0), v.get("iron", 0), v.get("vitc", 0),
                json.dumps(portions[i][:12])))
    n += 1
db.execute("INSERT INTO foods_fts(rowid, name) SELECT id, name FROM foods")
db.execute("INSERT INTO foods_fts(foods_fts) VALUES('optimize')")
db.commit(); db.execute("VACUUM"); db.close()
print(n, "foods ->", out, os.path.getsize(out) // 1024, "KB")
