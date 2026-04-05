# AuraTracker

A World of Warcraft addon for **WotLK 3.3.5** (Interface 30300) that tracks auras, cooldowns, trinket procs, snapshots, and buff/debuff information via customisable icon bars overlaid on the game UI.

---

## Features

- **Aura tracking** – track player/target/focus buffs and debuffs by spell ID, including "only mine" filtering and smart-group support for raid/party members
- **Cooldown tracking** – show spell cooldown sweeps with optional GCD suppression
- **Cooldown-aura hybrid** – display an icon that reflects an aura while it is active, then the cooldown sweep after it fades
- **Trinket / internal-CD tracking** – detect trinket procs via the combat log; icons hide automatically when the trinket is not equipped and show a 30-second swap cooldown when swapped
- **Weapon enchant tracking** – track temporary weapon enchants (sharpening stones, imbues, etc.) by main-hand or off-hand slot
- **Totem tracking** – one icon per shaman totem element slot automatically follows whichever totem of that element is active
- **Snapshot tracking** – tracks spec-specific damage-window buffs via the combat log for advanced display
- **Bar import / export** – share bar configurations as Base64 strings via the settings UI
- **Drag-and-drop setup** – drag spells, items, or aura buttons directly onto a bar to add them; drag icons within a bar to reorder them
- **Per-icon action conditionals** – WeakAuras-style conditions (health %, resource %, remaining duration, stack count) that trigger a pulsing glow or a sound alert
- **Load conditions** – show/hide entire bars or individual icons based on in-combat state, alive/dead, mounted, vehicle UI, talent, glyph, group type, unit health, or active aura
- **Edit mode** – drag bars anywhere on screen with `/at editmode`
- **Multiple bars** – create as many bars as needed, each with independent settings (direction, icon size, spacing, class/spec restriction, etc.)
- **Skins** – visual theming via LibSharedMedia-3.0 and custom skin helpers

---

## Installation

1. Download or clone this repository.
2. Place the `AuraTracker` folder inside your WoW `Interface/AddOns/` directory.
3. Restart WoW or reload your UI (`/reload`).

The folder must be named exactly `AuraTracker`.

---

## Slash Commands

| Command | Effect |
|---|---|
| `/auratracker` or `/at` | Open the settings panel |
| `/at editmode` or `/at move` | Toggle drag-to-reposition mode for bars |

---

## Usage

### Opening Settings

Type `/at` in chat to open the settings panel. From here you can:

- Create, rename, and delete bars
- Configure bar direction (horizontal / vertical), icon size, spacing, and scale
- Add and remove tracked items per bar
- Edit per-icon display mode, load conditions, and action conditionals

### Adding Items to a Bar

The quickest way to add an item is drag-and-drop:

- **Spell / ability** – drag from your spellbook or action bar onto the AuraTracker drop zone
- **Buff / debuff** – drag from the default buff/debuff frame onto the drop zone
- **Item** – drag from your bag onto the drop zone
- **Temporary weapon enchant** – drag from the buff-frame temporary enchant button

Alternatively, use the settings panel to add items by spell ID or item ID.

### Display Modes

Each tracked item has a display mode:

| Mode | Behaviour |
|---|---|
| **Always** | Icon is always visible (dim when inactive, bright when active) |
| **Active only** | Icon only shows when the aura/cooldown is active |
| **Missing only** | Icon only shows when the aura is absent |

### Load Conditions

Load conditions gate the **visibility** of a bar or individual icon. All active conditions must be satisfied simultaneously (AND logic). Available conditions:

- **In Combat** – yes/no
- **Alive** – alive/dead
- **Mounted** – yes/no
- **Vehicle UI** – yes/no
- **In Group** – solo / party / raid / party or raid
- **Talent** – player has a specific talent rank
- **Glyph** – player has a specific glyph socketed
- **Unit HP** – unit health percentage comparison (icon-only)
- **Aura** – unit has / does not have a specific aura (icon-only)

### Action Conditionals (Glow & Sound)

Per-icon conditionals fire when a condition becomes true. Each conditional can:

- Apply a **pulsing glow** border to the icon (configurable colour)
- Play a **sound** (uses LibSharedMedia-3.0 — any sound registered by installed addons is available)

Available check types: health %, resource %, remaining duration, stack count.

### Snapshot Tracking

The snapshot tracker watches the combat log for spec-specific buff windows (e.g. trinket procs that buff periodic damage). A small text overlay on the icon shows the snapshot value. No manual configuration is required; snapshot rules are built into the addon's data files.

---

## Configuration Data

The following data files under `Data/` drive item behaviour:

| File | Contents |
|---|---|
| `Config.lua` | Track-type enums, aura filters, display-mode defaults, GCD constants |
| `TrinketData.lua` | Per-trinket ICD durations and proc spell IDs |
| `TrinketProcData.lua` | Extended trinket proc data |
| `ExampleBars.lua` / `ExampleBarsB.lua` | Preset bar configurations shipped with the addon |
| `ConfigWeaponEnchant.lua` | Weapon enchant item data |
| `ConfigTotem.lua` | Shaman totem slot data |

---

## Libraries

AuraTracker vendors the following libraries under `Libraries/`:

- **Ace3** (AceAddon, AceEvent, AceConsole, AceDB, AceConfig, AceConfigDialog, AceGUI)
- **LibSharedMedia-3.0** – media (sound, font, texture) sharing between addons
- **LibStub** – library versioning
- **LibFramePool-1.0** – frame recycling pool
- **LibEditmode-1.0** – drag-to-reposition support

---

## Saved Variables

Settings are stored in `SimpleAuraTrackerDB` (WTF folder). The database is profile-based via AceDB; each character defaults to the `"Default"` profile. Bar configurations, tracked item settings, and custom mappings are all stored per-profile.

---

## Compatibility

- **WotLK 3.3.5** (Interface version 30300) only.
- Does not use Retail or Classic-era APIs.
