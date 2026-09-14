# Changelog

## 1.1.0

- Enables achievements for modded, cheated-character, and cheated-world states.
- Replaces the separate EnableAchievments dependency.
- Keeps all stored cheat markers untouched.

## 1.0.0

- Hides all Valheim 1.0.7 cheat-related localization messages.
- Hides the raw `Cheater!` statistics label.
- Preserves character, world, and item cheat flags unchanged.
# 1.2.0

- Rechecks already known materials and crafting stations after login.
- Restores missing crafting recipes and build pieces through Valheim's native discovery method.
- Existing known recipes are not reset or announced again.
# 1.2.1

- Added a safe one-time replay of currently available recipe and build-piece unlock notifications.
- Preserves every previous unlock record after rebuilding the available list.
- Added a recipe recheck after item discovery as protection against modded inventory-transfer paths.
