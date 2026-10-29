#!/usr/bin/env python3
"""Copy a Scrap Mechanic recipe JSON, dropping production-blacklisted items.

The craftbot grid is loaded by the engine directly from the recipe file, so
filtering g_craftingRecipeSets in Lua removes craftability but not the visible
grid entry. Feed the craftbot a sanitized file instead.

Usage:
    python3 tools/filter_recipes.py SOURCE OUTPUT BLACKLIST.json
"""

import json
import re
import sys


def load_game_json(path):
    text = open(path, encoding="utf-8-sig").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return json.loads(text)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)

    source, output, blacklist_path = sys.argv[1:]
    blacklist = set(load_game_json(blacklist_path)["items"].keys())

    recipes = load_game_json(source)
    kept = []
    removed = 0
    for recipe in recipes:
        item_id = recipe.get("itemId", "").lower()
        ingredients = [i.get("itemId", "").lower() for i in recipe.get("ingredientList", [])]
        if item_id in blacklist or any(u in blacklist for u in ingredients):
            removed += 1
            continue
        kept.append(recipe)

    with open(output, "w", encoding="utf-8") as f:
        json.dump(kept, f, indent="\t")
        f.write("\n")

    print(f"{source} -> {output}: kept {len(kept)}, removed {removed}")


if __name__ == "__main__":
    main()
