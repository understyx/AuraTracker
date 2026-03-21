# AuraTracker – Coding Agent Instructions

## Project Overview

AuraTracker is a World of Warcraft addon targeting **WotLK 3.3.5** (Interface version 30300). It tracks auras, cooldowns, trinket procs, snapshots, and other buff/debuff information via icon bars overlaid on the game UI.

## Repository Layout

```
AuraTracker/
├── AuraTracker.toc          # Addon manifest; defines load order
├── AuraTracker.lua          # Core controller (lifecycle, events)
├── BarManager.lua           # Bar CRUD and rebuild logic
├── ItemFactory.lua          # Tracked-item creation helpers
├── EquipmentManager.lua     # Trinket/ring slot helpers
├── Icon.lua                 # Single icon rendering + conditionals
├── Bar.lua                  # Bar frame construction
├── Conditionals.lua         # Load conditions + action conditionals
├── UpdateEngine.lua         # Periodic update ticker
├── SnapshotTracker.lua      # CLEU-based snapshot tracking
├── TrackedItem.lua          # TrackedItem data model
├── DragDrop.lua             # Drag-and-drop for icon reordering
├── Config.lua               # Static configuration tables
├── TrinketData.lua          # Trinket proc/ICD data
├── ExampleBars.lua          # Preset bar definitions
├── Skin.lua                 # Visual skin helpers
├── MiniTalentWidget.lua     # Talent widget UI
├── SavedVariables.lua       # DB schema + migration helpers
├── Settings/
│   ├── Settings.lua         # Main settings panel + SettingsUtils export
│   ├── IconEditorUI.lua     # Per-icon editor panel
│   ├── BarSettingsUI.lua    # Per-bar settings panel
│   ├── ConditionUI.lua      # Condition builder UI
│   └── SettingsMappings.lua # Key-to-display-name mappings
└── Libraries/               # Vendored libraries (Ace3, LibSharedMedia, etc.)
```

## Module Pattern

All modules follow the `ns.AuraTracker.ModuleName` pattern:

```lua
local ns = select(2, ...)
local AuraTracker = ns.AuraTracker.Controller  -- or other module name
```

Load order in `AuraTracker.toc` determines when modules are available. Runtime method calls across files work because all files load before game events fire.

## Key Conventions

- **WotLK 3.3.5 APIs only** – no Retail/Classic-era API differences. Key APIs:
  - `UnitAffectingCombat`, `UnitIsDeadOrGhost`, `IsMounted`, `UnitHasVehicleUI`, `UnitInVehicle`
  - `UnitPower` / `UnitPowerMax` for mana/rage/energy/runic power
  - `GetGlyphSocketInfo(1-6)` returns `(enabled, glyphType, tooltipIndex, spellId, icon)`
  - `GetNumRaidMembers()` / `GetNumPartyMembers()` for group checks
  - CLEU args via `...`: `timestamp(1), subEvent(2), sourceGUID(3), sourceName(4), sourceFlags(5), destGUID(6), destName(7), destFlags(8), spellId(9), spellName(10)`
  - No `CombatLogGetCurrentEventInfo()`

- **Sounds** – use LibSharedMedia-3.0. Sounds are stored as LSM names (e.g. `"Raid Warning"`) in `cond.sound`. `PlaySoundForKey` fetches via `LSM:Fetch("sound", key)`.

- **Conditional system** – two categories:
  - *Load Conditions* (bar + icon visibility, AND logic): `in_combat`, `alive`, `has_vehicle_ui`, `mounted`, `talent`, `glyph`, `in_group`, `unit_hp` (icon-only)
  - *Action Conditionals* (icon-only, glow/sound): `unit_hp`, `unit_power`, `remaining`, `stacks`
  - DB fields: `loadConditions[]` for visibility, `conditionals[]` for actions

- **Settings subfolder** – settings-related files live in `Settings/`: `ConditionUI.lua`, `Settings.lua`, `IconEditorUI.lua`, `BarSettingsUI.lua`, `SettingsMappings.lua`. Core files remain in the root.

- **IconEditorUI ordering** – use `orderBase` offsets: display opts (10–14), load conditions (15), also-track section (20–24+), action conditionals (45), reorder (50–52), danger zone (99–100).

- **INTERNAL_CD items** hide when not equipped. `SyncEquipState` checks trinket slots (WoW inventory slot IDs 13–14) and ring slots (11–12). Per-slot `_prevTrinketSlots` tracking detects t1↔t2 swaps.

- **Bar conditional recheck** – `RecheckBarConditions()` in `BarManager.lua` polls all DB bars every 100 ms (via `UpdateEngine` tick), comparing `ShouldShowBar()` against current visibility. Only calls `RebuildBar()` when state actually changes.

## Linting / Building / Testing

There is **no build system or test infrastructure**. To syntax-check a Lua file:

```bash
luac5.1 -p <file.lua>
```

Run this on any file you modify before committing.

There is no automated test suite. Validate changes by syntax-checking affected files and manually reasoning through the logic. Do not add new build or testing tools unless they are explicitly requested.

## Adding or Changing Files

1. If adding a new `.lua` file, add it to `AuraTracker.toc` in the correct load-order position.
2. Follow the `ns.AuraTracker.ModuleName` module pattern.
3. Syntax-check with `luac5.1 -p <file>` after editing.
4. Do not change the WotLK interface version (`30300`) or vendored libraries unless explicitly asked.
