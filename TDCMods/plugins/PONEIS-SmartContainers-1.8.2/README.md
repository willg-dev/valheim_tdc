# SmartContainers (Valheim 1.0 fork)

Unofficial community port of **Flueno/ZOR SmartContainers** for **Valheim 1.0** (Unity 6).

Original idea and design belong to Flueno / ZOR ([Nexus mod 332](https://www.nexusmods.com/valheim/mods/332)).  
This package rebuilds and updates that mod so it loads again after the 1.0 release.

> Want to quickly drop your loot? Tired of looking for the chest with a specific item-stack just to store more of it? Teach your containers to arrange items with their neighbors.

Also available on **[Nexus Mods](https://www.nexusmods.com/valheim/mods/3656)**. Support for this fork is handled there (see below).

---

## Support / Bug reports

**Please report bugs, crashes, compatibility issues and feedback on Nexus Mods:**  
**[nexusmods.com/valheim/mods/3656](https://www.nexusmods.com/valheim/mods/3656)**

- Use the **Bugs** tab for reproducible problems (include game version, BepInEx version, and a snippet from `BepInEx/LogOutput.log` when possible).
- Use the **Posts** tab for questions, multiplayer notes and general feedback.
- Feature requests are welcome on Nexus Posts as well.

Do **not** use the abandoned original [Nexus mod 332](https://www.nexusmods.com/valheim/mods/332) for support of this fork — that page is credits only.

Thunderstore comments are **not** monitored for support.

When filing a bug, please include:

1. Valheim version (1.0.x)
2. BepInExPack version (expected: 5.4.2350+)
3. SmartContainers version (as shown in `BepInEx/LogOutput.log`)
4. Whether it happens in singleplayer or multiplayer
5. Relevant lines from `BepInEx/LogOutput.log` (especially `SmartContainers` / Harmony errors)

---

## Support the author

If this Valheim 1.0 fork helps you out, you can support continued maintenance with a donation on Ko-fi:

**[ko-fi.com/tudoecriativo](https://ko-fi.com/tudoecriativo)**

Tips help cover the time spent keeping the mod working after game updates. Thank you!

---

## Features

- Automatically sends items you put into a chest to other nearby chests that already contain the same item-stack.
- Routes same-kinded items to their siblings (example: copper ore goes to a chest that already has tin ore).
- Create custom item-groups from any combination — put carrots, stones and feathers in one box, click the button, and from then on carrots can route to a chest that has feathers.
- Optional unload button to dump configured loot from your inventory into the correct nearby chests in one click.
- HUD message, sound and VFX feedback when items are successfully routed.
- Multiplayer-aware options to skip or block chests currently used by other players.

---

## How it works

When you move an item stack into a container with **Ctrl + Click**:

1. If the current container is full or does not already have that item:
   - Search nearby containers for the same item-stack and route there if there is space.
2. If none found and grouping is enabled:
   - Search nearby containers that contain items from a matching group (user groups, system groups, prefix/postfix patterns, or item-type groups).

In short: if a group contains your item and a nearby chest already has another member of that group, your item can go to that chest.

---

## Controls

| Input | Action |
|---|---|
| `Ctrl + Click` | Move stack and trigger SmartContainers routing |
| `Ctrl + L + Click` | Same as above, but also prints the item name to the F5 console |
| Chest UI button `+` | Create / merge custom item-groups from the opened chest |
| Chest UI button `>>` | Unload configured inventory items into nearby chests (if Unload is enabled) |
| `Shift + click +` | Add current chest item names to unload allow-list |
| `Ctrl + click +` | Add current chest item names to unload skip-list |

Gamepad bindings are configurable (create-group, unload filters, etc.).

---

## General configuration

Config file: `BepInEx/config/flueno.SmartContainers.cfg`  
Also editable in-game with Configuration Manager (F1).

| Option | Description |
|---|---|
| `enabled` | Master toggle |
| `range` | Radius used to find nearby containers |
| `onlyStackableItems` | If enabled, tools/weapons/armor are not rearranged |
| `hudMessageEnabled` / `hudMessageText` | Message when an item is routed to another chest |
| `audioFeedbackEnabled` | Play sound on successful transfer |
| `effectFeedbackEnabled` | Highlight destination chests |
| `concurrentChestModificationWorkaround` | Multiplayer safety: ignore / skip opened chests / block if another player is using nearby chests |

---

## Item grouping

Ways to define a group:

- Explicit item-name lists in `[ItemGroup]`
- Name **prefixes** (example: `trophy`boar and `trophy`troll)
- Name **postfixes** (example: carrot`Seeds` and turnip`Seeds`)
- In-game **item-type** (Tool, Weapon, Ammo, Armor, Trophy, …)
- Optional fuzzy grouping by broader item-type families

### Grouping options

| Option | Description |
|---|---|
| `Grouping.enabled` | Enables group routing after same-stack lookup fails |
| `itemTypeGroupsEnabled` | Group by item-type |
| `fuzzyGroupingEnabled` | Broader type matching |
| `groupingKeyModifier` | Modifier required for grouping (default LeftControl) |
| `createGroupBtnEnabled` | Shows the `+` button on chest UI |
| `mergePromptEnabled` | Shows merge/extend dialog when groups already overlap |
| `createGroupBtnPos` | Button position on inventory UI |

### Preconfigured item groups

```
valuables = ruby,coins,amber,amberpearl
ore = copperore,flametalore,ironore,silverore,tinore,ironscrap,blackmetalscrap
rock = stone,flint,obsidian
ingots = copper,bronze,flametal,iron,silver,tin,blackmetal
wood = wood,finewood,corewood,elderbark,roundlog
mushrooms = Mushroom,MushroomBlue,MushroomYellow,mushroomcommon
berries = Blueberries,raspberries,cloudberries,honey
vegetables = Carrot,Turnip
cookedMeat = CookedLoxMeat,NeckTailGrilled,MeatCooked,FishCooked,SerpentMeatCooked
food = CarrotSoup,Sausages,QueensJam,SerpentStew,TurnipStew,BloodPudding
```

### Prefix / postfix groups

```
[PrefixedItemGroups] prefixes = trophy,mead,arrow,armor,cape,helmet,...
[PostfixedItemGroups] posfixes = cone,seeds,pelt,hide,berries
```

### Custom groups

1. Put the desired items in a chest.
2. Click the `+` button.
3. If those items already belong to existing groups, a dialog lets you **Extend**, **Extend & Merge**, or **Merge All**.

Disable a preconfigured group by clearing its value in config / Configuration Manager.

You can also add groups manually, example:

```
fishes = FishRaw,FishCooked
```

(Game restart may be required for some manual edits.)

---

## Unloading

Optional one-click inventory dump into relevant nearby chests.

| Option | Description |
|---|---|
| `Unload.enabled` | Enables unload logic + UI button |
| `nativeButton` | Reuse the vanilla stack button instead of creating `>>` |
| `groupsList` | Which `[ItemGroup]` ids can be unloaded |
| `itemsList` / `itemsSkipList` | Explicit allow / deny item names |
| `materialsFiltering` / `trophiesFiltering` / `consumableFiltering` | Allow whole item-types |
| `alwaysGrouping` | Always use grouping during unload |

Unload only moves non-equipped items that pass the filters, then routes them with the same nearby-chest logic.

---

## Installation

### r2modman / Thunderstore Mod Manager

1. Install this package.
2. Ensure **BepInExPack Valheim 5.4.2350+** is installed.
3. Launch the game from the mod manager.

### Manual

1. Install [BepInExPack Valheim](https://thunderstore.io/c/valheim/p/denikson/BepInExPack_Valheim/) `5.4.2350` or newer.
2. Extract `SmartContainers.dll` into `BepInEx/plugins`.
3. Start the game.
4. Confirm in `BepInEx/LogOutput.log`:
   - `Loading [Smart Containers Mod 1.8.0]`
   - `SmartContainers 1.8.0 loaded`

Recommended: Configuration Manager + `-console` launch option for F5 debugging.

---

## Valheim 1.0 port notes

- Rebuilt against Valheim 1.0 / Unity 6 assemblies.
- Harmony targets validated for current game methods (`Inventory.AddItem`, `StackAll`, container/player GUI hooks).
- Merge-group UI rewritten because vanilla `SplitDialog` changed in 1.0.
- Plugin GUID remains `flueno.SmartContainers` so existing configs keep working.

---

## Credits

- Original mod: **Flueno / ZOR** — [Nexus 332](https://www.nexusmods.com/valheim/mods/332) (abandoned; credits only)
- Earlier Thunderstore mirrors: Flueno, ZOR, Roses
- This Valheim 1.0 fork/rebuild: unofficial maintenance port based on the abandoned 2023 binary

**Bugs and support for this fork → [Nexus Mods 3656](https://www.nexusmods.com/valheim/mods/3656)** (not the original 332 page, and not Thunderstore comments).

---

## Changelog

### 1.8.2
- Documentation: link official Nexus page for this fork ([mods/3656](https://www.nexusmods.com/valheim/mods/3656))
- Documentation: add Ko-fi donation link ([ko-fi.com/tudoecriativo](https://ko-fi.com/tudoecriativo))
- No gameplay / DLL changes vs 1.8.0

### 1.8.1
- Documentation: add Ko-fi donation link for supporting maintenance ([ko-fi.com/tudoecriativo](https://ko-fi.com/tudoecriativo))
- No gameplay / DLL changes vs 1.8.0

### 1.8.0
- Port to Valheim 1.0 (Unity 6)
- Rebuild from decompiled 1.7.x sources
- Update BepInEx dependency to 5.4.2350+
- Rewrite merge-group dialog for new inventory UI
- Keep original config GUID for compatibility
- Support / bug reports directed to Nexus Mods
