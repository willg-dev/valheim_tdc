# No Cheat Text

Enjoy a clean interface and keep earning achievements while playing modded Valheim.

No Cheat Text is a lightweight client-side mod for Valheim 1.0.12. It removes the persistent cheat-related labels and notifications introduced with the achievement system, while also allowing achievements in modded games and saves marked as cheated.

## Features

- Enables achievements while BepInEx or other mods are loaded.
- Enables achievements for characters and worlds marked as cheated.
- Hides the cheated-item warning in item tooltips.
- Hides the notification shown after picking up a cheated item.
- Hides temporary and permanent cheat warnings in the Achievements screen.
- Hides the `Cheater!` line in the character statistics dialog.
- Can hide the cheat-command confirmation text.
- Rechecks known materials and crafting stations after login and restores legitimately available recipes or build pieces that were previously missed.
- Can replay all currently available recipe and build-piece unlock notifications once after updating, while preserving previous unlock records.
- Works entirely on the client; no server installation or synchronization is required.

## What the mod does not change

No Cheat Text does not edit or remove the saved cheat markers attached to characters, worlds, or items. It only changes achievement eligibility at runtime and suppresses the related interface text.

This means uninstalling the mod restores Valheim's normal behavior. Your items and save data are not silently rewritten.

The mod does not automatically grant achievements. You must still satisfy each achievement's normal gameplay requirements.

## Installation

### Thunderstore Mod Manager or r2modman

1. Install No Cheat Text and its BepInEx dependency.
2. Start Valheim with **Start modded**.

### Manual installation

1. Install BepInExPack Valheim 5.4.2350 or later.
2. Copy `NoCheatText.dll` into `BepInEx/plugins/NoCheatText/`.
3. Start the game once to generate the configuration file.

## Configuration

The configuration file is created at:

`BepInEx/config/codex.valheim.nocheattext.cfg`

- `General / Enabled` — controls the interface-text suppression features.
- `Achievements / Enabled` — allows achievements despite modded and cheated-state checks.
- `General / HideCommandConfirmation` — hides the text of Valheim's cheat-command confirmation prompt. The underlying confirmation requirement remains active.
- `Recipes / RepairMissingRecipesOnLogin` — rechecks the character's discoveries after login and unlocks only missing recipes and build pieces for which the normal requirements are already known.
- `Recipes / ReplayUnlockNotificationsOnce` — replays currently eligible unlocks once and automatically changes itself to `false` after success.

Achievement enabling and text suppression can be configured independently.

## Compatibility

No Cheat Text patches Valheim's achievement checks and localization output. It should not be installed together with another achievement-enabler mod, since those mods modify the same checks.

Remove or disable `Yorimor-EnableAchievments`, `AchievementEnabler`, `Unshamed`, or similar mods before using No Cheat Text.

No Cheat Text does not require Jotunn or ServerSync.

## Multiplayer

The mod is client-side. Each player who wants hidden warnings and enabled achievements should install it locally. Dedicated servers do not need it.

## Tested target

- Valheim 1.0.12
- BepInExPack Valheim 5.4.2350

Future Valheim updates may change achievement or interface methods. Check the changelog after major game updates.

## AI-assisted development disclosure

Significant portions of this mod and its documentation were created with AI assistance and reviewed against the Valheim 1.0.12 game assemblies. Please apply Thunderstore's **AI Generated** category when publishing the package.
