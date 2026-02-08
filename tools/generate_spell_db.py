#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from dataclasses import dataclass
from typing import Any


CLASS_MASK: dict[str, int] = {
    "WARRIOR": 1,
    "PALADIN": 2,
    "HUNTER": 4,
    "ROGUE": 8,
    "PRIEST": 16,
    "SHAMAN": 64,
    "MAGE": 128,
    "WARLOCK": 256,
    "DRUID": 1024,
}

CLASS_ABILITIES_PAGES: dict[str, dict[str, str]] = {
    "classic": {
        "WARRIOR": "https://www.wowhead.com/classic/abilities/warrior",
        "PALADIN": "https://www.wowhead.com/classic/abilities/paladin",
        "HUNTER": "https://www.wowhead.com/classic/abilities/hunter",
        "ROGUE": "https://www.wowhead.com/classic/abilities/rogue",
        "PRIEST": "https://www.wowhead.com/classic/abilities/priest",
        "SHAMAN": "https://www.wowhead.com/classic/abilities/shaman",
        "MAGE": "https://www.wowhead.com/classic/abilities/mage",
        "WARLOCK": "https://www.wowhead.com/classic/abilities/warlock",
        "DRUID": "https://www.wowhead.com/classic/abilities/druid",
    },
    "tbc": {
        "WARRIOR": "https://www.wowhead.com/tbc/abilities/warrior",
        "PALADIN": "https://www.wowhead.com/tbc/abilities/paladin",
        "HUNTER": "https://www.wowhead.com/tbc/abilities/hunter",
        "ROGUE": "https://www.wowhead.com/tbc/abilities/rogue",
        "PRIEST": "https://www.wowhead.com/tbc/abilities/priest",
        "SHAMAN": "https://www.wowhead.com/tbc/abilities/shaman",
        "MAGE": "https://www.wowhead.com/tbc/abilities/mage",
        "WARLOCK": "https://www.wowhead.com/tbc/abilities/warlock",
        "DRUID": "https://www.wowhead.com/tbc/abilities/druid",
    },
}


@dataclass(frozen=True)
class SpellRank:
    spell_id: int
    name: str
    rank: str
    level: int
    training_cost: int
    spec_id: int


def fetch(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Spellbook-Pro generator (local)/1.0",
            "Accept": "text/html",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.read().decode("utf-8", errors="replace")


def extract_js_array(page: str, var_name: str) -> str:
    m = re.search(rf"\bvar\s+{re.escape(var_name)}\s*=\s*\[", page)
    if not m:
        raise RuntimeError(f"Could not find var {var_name!r}")
    start = m.end() - 1

    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(page)):
        ch = page[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return page[start : i + 1]
    raise RuntimeError(f"Unterminated array for var {var_name!r}")


def js_object_array_to_json(text: str) -> str:
    # Wowhead embeds JS object literals that are "almost JSON" but may omit quotes on some keys.
    # Convert `{foo:1, "bar":2}` to `{"foo":1, "bar":2}`.
    return re.sub(r'([{\[,])\s*([A-Za-z_][A-Za-z0-9_]*)\s*:', r'\1"\2":', text)


def normalize_rank(rank: str) -> str:
    return (rank or "").strip()


def rank_number(rank: str) -> int:
    m = re.search(r"(\d+)", rank or "")
    return int(m.group(1)) if m else 0


def class_spells_from_listview(listview: list[dict[str, Any]], class_mask: int) -> list[SpellRank]:
    ranks: list[SpellRank] = []
    for row in listview:
        if row.get("cat") != 7:
            continue
        if row.get("reqclass") != class_mask:
            continue
        # Exclude Season of Discovery-specific entries.
        if row.get("seasonId") is not None:
            continue
        spell_id = row.get("id")
        name = (row.get("name") or "").strip()
        rank = normalize_rank((row.get("rank") or "").strip())
        level = row.get("level")
        training_cost = row.get("trainingcost")
        skill = row.get("skill")
        if not isinstance(spell_id, int) or not name:
            continue
        spec_id = 0
        if isinstance(skill, list) and skill and isinstance(skill[0], int):
            spec_id = int(skill[0])
        ranks.append(
            SpellRank(
                spell_id=spell_id,
                name=name,
                rank=rank,
                level=int(level) if isinstance(level, int) else 0,
                training_cost=int(training_cost) if isinstance(training_cost, int) else 0,
                spec_id=spec_id,
            )
        )

    ranks.sort(key=lambda r: (r.name.lower(), rank_number(r.rank), r.spell_id))
    return ranks


def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def emit_lua(db: dict[str, dict[str, list[SpellRank]]], *, var_name: str) -> str:
    out: list[str] = []
    out.append("-- Generated by tools/generate_spell_db.py; do not edit by hand.")
    out.append(f"{var_name} = {{")
    out.append("  version = 1,")
    out.append("  classes = {")

    for class_token in sorted(db.keys()):
        out.append(f'    ["{class_token}"] = {{')
        spells = db[class_token]
        for spell_name in sorted(spells.keys(), key=lambda x: x.lower()):
            out.append(f'      ["{lua_escape(spell_name)}"] = {{')
            for rank in spells[spell_name]:
                rank_str = lua_escape(rank.rank)
                out.append(
                    f'        {{ id = {rank.spell_id}, rank = "{rank_str}", level = {rank.level}, cost = {rank.training_cost}, spec = {rank.spec_id} }},'
                )
            out.append("      },")
        out.append("    },")

    out.append("  },")
    out.append("}")
    out.append("")
    return "\n".join(out)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate Spellbook-Pro spell DB from Wowhead.")
    parser.add_argument(
        "--expansion",
        choices=sorted(CLASS_ABILITIES_PAGES.keys()),
        default="classic",
        help="Which Wowhead dataset to use (default: classic).",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pages = CLASS_ABILITIES_PAGES[args.expansion]
    db: dict[str, dict[str, list[SpellRank]]] = {}
    for class_token, mask in CLASS_MASK.items():
        url = pages[class_token]
        page = fetch(url)
        array_text = extract_js_array(page, "listviewspells")
        listview = json.loads(js_object_array_to_json(array_text))

        ranks = class_spells_from_listview(listview, mask)

        by_name: dict[str, list[SpellRank]] = {}
        for rank in ranks:
            by_name.setdefault(rank.name, []).append(rank)

        db[class_token] = by_name
        print(f"{class_token}: {len(by_name)} spells, {len(ranks)} ranks", file=sys.stderr)

    var_name = "SpellbookProSpellDB_BCC" if args.expansion == "tbc" else "SpellbookProSpellDB"
    sys.stdout.write(emit_lua(db, var_name=var_name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
