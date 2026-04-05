# AuraTracker – Coding Agent Instructions

## Project Overview

AuraTracker is a World of Warcraft addon targeting **WotLK 3.3.5** (Interface version 30300). It tracks auras, cooldowns, trinket procs, snapshots, and other buff/debuff information via icon bars overlaid on the game UI.

## Repository Layout

```
AuraTracker/
├── AuraTracker.toc              # Addon manifest; defines load order
├── AuraTracker.lua              # Core controller (lifecycle, events, slash commands)
├── SavedVariables.lua           # Saved DB snapshot (committed for reference)
├── Core/
│   ├── BarManager.lua           # Bar CRUD, rebuild, and static-cache logic
│   ├── BarVisibility.lua        # ShouldShowBar / RecheckBarConditions
│   ├── BarImportExport.lua      # Base64 bar share/import helpers
│   ├── ItemFactory.lua          # Tracked-item creation helpers (spells, auras)
│   ├── ItemFactoryEnchantTotem.lua # Weapon-enchant and totem item creation
│   ├── EquipmentManager.lua     # Trinket/ring slot tracking and swap CD
│   └── UpdateEngine.lua         # Periodic update ticker and GCD tracking
├── Data/
│   ├── Config.lua               # TrackType/DisplayMode/AuraFilter enums, GCD constants
│   ├── ConfigWeaponEnchant.lua  # Weapon enchant item data
│   ├── ConfigTotem.lua          # Shaman totem slot data
│   ├── TrinketData.lua          # Per-trinket ICD durations
│   ├── TrinketProcData.lua      # Extended trinket proc data
│   ├── ExampleBars.lua          # Preset bar configurations (set A)
│   └── ExampleBarsB.lua         # Preset bar configurations (set B)
├── Display/
│   ├── Icon.lua                 # Icon lifecycle (New / Refresh / ShouldShow)
│   ├── IconRender.lua           # Icon rendering helpers (active/inactive/ICD)
│   ├── IconText.lua             # Cooldown text and stack count overlays
│   ├── Bar.lua                  # Bar frame construction and icon layout
│   ├── DragDrop.lua             # Drop-zone creation and drag state
│   ├── DragDropHooks.lua        # Hooks into buff/action/enchant/pet buttons
│   ├── Skin.lua                 # Visual skin helpers
│   ├── SkinTabs.lua             # Tab skin helpers
│   ├── SkinDropdown.lua         # Dropdown skin helpers
│   ├── SkinWidgets.lua          # Widget skin helpers
│   ├── MiniTalentWidget.lua     # Talent widget UI
│   └── FramePicker.lua          # Frame-anchor picker UI
├── Tracking/
│   ├── Conditionals.lua         # Sound options, comparison helpers, LoadCheckType enums
│   ├── ConditionalChecks.lua    # CheckLoadCondition / CheckAllLoadConditions
│   ├── ConditionalActions.lua   # CheckActionCondition / EvaluateActions / SetGlow
│   ├── SnapshotData.lua         # Snapshot rule tables
│   ├── SnapshotTracker.lua      # CLEU-based snapshot tracking
│   ├── TrackedItem.lua          # TrackedItem data model and base methods
│   ├── TrackedItemUpdates.lua   # Refresh / aura-query / cooldown-query logic
│   └── TrackedItemSpecial.lua   # INTERNAL_CD / weapon-enchant / totem item logic
├── Settings/
│   ├── Settings.lua             # Main settings panel + SettingsUtils export
│   ├── MainFrame.lua            # Settings window frame construction
│   ├── BarOptions.lua           # Bar list and bar-level option injection
│   ├── BarSettingsUI.lua        # Per-bar settings panel
│   ├── IconEditorUI.lua         # Per-icon editor panel (main entry point)
│   ├── IconEditorOptions.lua    # Display/mode options injected into icon editor
│   ├── IconActionsUI.lua        # On-show/on-hide/on-click action configuration
│   ├── ConditionUI.lua          # Shared condition-builder UI helpers
│   ├── LoadConditionUI.lua      # Load condition section builder
│   ├── ActionConditionUI.lua    # Action conditional section builder
│   └── SettingsMappings.lua     # Key-to-display-name mappings for dropdowns
└── Libraries/                   # Vendored libraries (Ace3, LibSharedMedia, etc.)
```

## Module Pattern

All modules follow the `ns.AuraTracker.ModuleName` pattern:

```lua
local _, ns = ...
ns.AuraTracker = ns.AuraTracker or {}

local MyModule = {}
ns.AuraTracker.MyModule = MyModule
```

The main controller (`AuraTracker.lua`) creates the Ace3 addon object and stores it as `ns.AuraTracker.Controller`. Other files that need to add methods to the controller do:

```lua
local AuraTracker = ns.AuraTracker.Controller
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

- **Sounds** – use LibSharedMedia-3.0. Sounds are stored as LSM names (e.g. `"Raid Warning"`) in `cond.sound`. `PlaySoundForKey` fetches via `LSM:Fetch("sound", key)`. Old DB keys (e.g. `RAID_WARNING`) are auto-migrated via `OLD_SOUND_KEYS` in `Conditionals.lua`.

- **Conditional system** – two categories:
  - *Load Conditions* (`Tracking/ConditionalChecks.lua`) – bar + icon visibility, AND logic: `in_combat`, `alive`, `has_vehicle_ui`, `mounted`, `talent`, `glyph`, `in_group`, `unit_hp` (icon-only), `aura` (icon-only)
  - *Action Conditionals* (`Tracking/ConditionalActions.lua`) – icon-only, glow/sound: `unit_hp`, `unit_power`, `remaining`, `stacks`
  - DB fields: `loadConditions[]` for visibility, `conditionals[]` for actions

- **IconEditorUI ordering** – use `orderBase` offsets: display opts (10–14), load conditions (15), also-track section (20–24+), action conditionals (45), reorder (50–52), danger zone (99–100).

- **INTERNAL_CD items** hide when not equipped. `SyncEquipState` (in `Core/EquipmentManager.lua`) checks trinket slots (WoW inventory slot IDs 13–14) and ring slots (11–12). Per-slot `_prevTrinketSlots` tracking detects t1↔t2 swaps.

- **Bar conditional recheck** – `RecheckBarConditions()` in `Core/BarVisibility.lua` polls all DB bars every 100 ms (via `UpdateEngine` tick), comparing `ShouldShowBar()` against current visibility. Only calls `RebuildBar()` when state actually changes.

- **Smart group** – `Conditionals:GetSmartGroupUnits()` returns raid tokens in a raid, player+party tokens in a party, or just `{ "player" }` solo. Used for `smart_group` aura/HP checks.

- **Sentinel IDs** – `Config.MAINHAND_ENCHANT_SLOT_ID = -1`, `Config.OFFHAND_ENCHANT_SLOT_ID = -2`. Totem element slots use `-10` through `-12`. These negative IDs are safe because real WoW IDs are always positive.

## Linting / Building / Testing

There is **no build system or test infrastructure**. To syntax-check a Lua file:

```bash
luac5.1 -p <file.lua>
```

Run this on any file you modify before committing.

There is no automated test suite. Validate changes by syntax-checking affected files and manually reasoning through the logic. Do not add new build or testing tools unless they are explicitly requested.

## Adding or Changing Files

1. If adding a new `.lua` file, place it in the appropriate subdirectory (`Core/`, `Data/`, `Display/`, `Tracking/`, or `Settings/`) and add it to `AuraTracker.toc` in the correct load-order position.
2. Follow the `ns.AuraTracker.ModuleName` module pattern.
3. Syntax-check with `luac5.1 -p <file>` after editing.
4. Do not change the WotLK interface version (`30300`) or vendored libraries unless explicitly asked.
