# BetterExtensionMod

A continuously updated monster and event expansion mod for Slay the Spire 2.

## Features

- Currently adds 26 custom monsters grouped into 21 custom encounters across Overgrowth, Hive, and Underdocks, including normal fights, elites, event combats, and multi-phase bosses.
- Introduces themed encounter sets such as spider nests, wildman warbands, ghost and predator hunts, parasite battles, harbor creature packs, lighthouse escorts, and the Broken Parts -> Ancient Remains fusion boss.
- Adds 2 custom events with branching outcomes: `Fox Shadow Under the Moon` and `Ancient Magic?`, including combat choices, card removal, enchantment rewards, relic rewards, and multiplayer-safe event handling.
- Adds 3 event relics with a connected gameplay chain: `Fox Companion`, `Proof of Existence`, and `Magic Curse`.
- Adds 23 custom Powers, 7 custom intents, and 1 custom status card to support mechanics such as companion AI, mimic reactions, fusion countdowns, hidden intents, bleed, drowning, mist evasion, and parasite intrusion.
- Includes custom monster visuals, pet/ally behavior support, and an in-combat monster intent graph / state-machine visualization overlay for complex AI patterns.
- Supports JSON-based multiplayer difficulty scaling with hot reload, with tuning by Act, encounter, monster, and individual Power.
- Multiplayer scaling supports a user-side editable JSON file that is generated automatically on first launch.
- A public in-game configuration panel is not available yet.

## Changes Since v0.1.5 

1. Multiplayer scaling reliability and sync checks
   - Config load priority now prefers `mods/BetterExtension/config/multiplayer_scaling.jsonc`, with fallback to the old AppData path and packaged defaults.
   - Editable config is auto-generated on first launch, and old user config is migrated when available.
   - JSON parser now accepts comments and trailing commas.
   - In multiplayer sessions, BetterExtension logs config source + fingerprint and injects this fingerprint into gameplay-relevant mod identity.
   - If peers use different scaling config data, the game blocks joining before run start via the built-in `Mod mismatch` flow.

2. Stuck-state fallback command
   - Added network-synced console command `skip`.
   - In combat: force-cleans live enemies and pushes combat to settlement flow (with safety fallback).
   - In event rooms: force-enables map travel, with fallback transition back to map room.

3. Stability and compatibility patches
   - Added game-over compatibility safety patch for score-line and badge insertion (`AddScoreLine` / `AddBadge`), including safer icon/control creation fallback paths.
   - Updated monster visuals wrapping logic to include explicit registry-based layouts.

4. Gameplay and balance updates
   - `MutantHorsehairWorm`: host summon pool now pulls from Hive regular encounters with explicit incompatible-target exclusions; max HP and reveal-heal values tuned.
   - `HarborSiren`: HP and multi-hit damage tuned; mist gain now has ascension-based scaling.
   - `BetterExtensionAssemblyPower`: artifact stacks granted to fused boss reduced (`5 -> 3`).
   - Localization text for selected monster/power entries refreshed.

## Compatibility

This mod is built to scale alongside other character mods. Verified compatibility entries will continue to be updated.

Currently verified with:

1. <https://www.nexusmods.com/slaythespire2/mods/302>
2. <https://www.nexusmods.com/slaythespire2/mods/346>

## Installation

1. Download the latest release package.
2. Place `BetterExtension.dll`, `BetterExtension.pck`, and `BetterExtension.json` in the same mod folder.
3. Move that folder into the `mods` directory inside the game installation folder.
4. Launch the game and enable **Better Extension**.

## Multiplayer Scaling JSON

1. Launch once after installing the mod to auto-generate an editable config:
   `mods/BetterExtension/config/multiplayer_scaling.jsonc`
2. Recommended Windows path:
   `\SteamLibrary\steamapps\common\Slay the Spire 2\mods\BetterExtension\config\multiplayer_scaling.jsonc`
3. Fallback compatibility path:
   `%APPDATA%\Godot\app_userdata\Slay the Spire 2\BetterExtension\config\multiplayer_scaling.json`
4. Edit JSON content and save. Runtime hot reload checks about every 1 second.
5. For multiplayer, every player must use the same JSON values, otherwise encounter scaling will diverge.
6. Multiplayer now injects a config fingerprint into the gameplay mod check list. If peers use different scaling config data, joining is blocked before entering the run and an in-game `Mod mismatch` popup is shown.

## Feedback

- Bilibili: <https://space.bilibili.com/589864971>
- QQ: `15948
- GitHub: <https://github.com/PnLament/BetterExtensionMod>

## Emergency Console Command

- `skip`: network-synced fallback command for stuck progression states.
- In combat, `skip` force-resolves combat and pushes to room-end settlement flow.
- In event rooms, `skip` force-opens map travel so the run can continue.
