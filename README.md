# Spellbook-Pro
Spellbook with always highest rank Spell Macros
Spellbook-Pro

Classic-era addon (Classic Era / SoD / Hardcore) that provides a separate spellbook window with buttons that always cast your highest known rank.

Usage
- Click the `Spellbook-Pro` button (top-left) or run `/sbp` to toggle the window.
- Drag entries onto your action bars.

Options (slash)
- `/sbp general` toggle showing the General tab spells
- `/sbp others` toggle showing other tabs (e.g. professions if they appear)
- `/sbp pet` toggle showing pet spells

Prebuilt multi-class spell DB (Wowhead)
- `SpellbookPro_SpellDB.lua` contains `SpellbookProSpellDB` (spell name -> ranks with spellID) for all player classes.
- To regenerate: `python3 tools/generate_spell_db.py > SpellbookPro_SpellDB.lua`
