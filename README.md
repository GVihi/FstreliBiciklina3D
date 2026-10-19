# FstreliBiciklina3D
Mostly vibe coded Godot game

# Roguelite Development Roadmap

> The game is already most of the way to a roguelite. It has runs made of rounds, a shop, perks that pair into duos, and bosses. Almost everything on this list is a layer on top of that, plus the missing "between runs" progression.

## Proper version control
- [ ] GitHub

## Big Design Choice

- [x] Decide on the game's long-term direction
  - [ ] Arcade score-attack with unlockables
  - [x] Full roguelite focus (recommended)

### Recommended Roguelite Structure

- [ ] Create runs of ~10 rounds
- [ ] Target 20–30 minute run duration
- [ ] Add final boss encounter
- [ ] Implement permanent unlocks between runs

---

# Milestone A: Menu, Game Flow, Saves & High Scores

## Menu & Game Flow

- [ ] Create title screen
  - [ ] Play button
  - [ ] Loadout button
  - [ ] Unlocks button
  - [ ] High Scores button
  - [ ] Settings button
  - [ ] Quit button

- [ ] Create proper pause menu

- [ ] Create run summary screen
  - [ ] Display score
  - [ ] Display kills
  - [ ] Display accuracy
  - [ ] Display best style rank
  - [ ] Display newly unlocked items

- [ ] Connect existing settings system to menus

## High Scores

- [ ] Implement local Top 10 leaderboard
- [ ] Add player name entry
- [ ] Support separate leaderboards per difficulty

### Daily Seed Mode

- [ ] Generate a daily seed
- [ ] Use same seed for all players on that day
- [ ] Add dedicated daily-run scoreboard
- [ ] Submit scores to Django web leaderboard
  - [ ] Implement REST API on Django web service
  - [ ] Implement Seed and leaderboard display

### Deferred

- [ ] Online leaderboard (future feature)

---

# Milestone B: Meta Currency, Unlocks & Skins

## Meta Progression

- [ ] Add meta currency
  - [ ] Earn from score
  - [ ] Earn from boss kills
  - [ ] Earn from challenges

- [ ] Keep meta currency separate from run cash

## Meta Unlocks

- [ ] Unlock starting perks
- [ ] Unlock additional weapons in shop pool
- [ ] Unlock cosmetics

## Difficulty Scaling

- [ ] Implement Heat system
- [ ] Allow multiple Heat modifiers
- [ ] Increase rewards for higher Heat levels

## Cosmetics & Skins

### Weapon Cosmetics

- [ ] Dart gun skins
- [ ] Worm skins

### UI Cosmetics

- [ ] Crosshair skins
- [ ] Hit effect skins

### World Cosmetics

- [ ] Cheerleader skins
- [ ] Rider bike skins
- [ ] Rider helmet skins

### Easy Cosmetic Variants

- [ ] Colour swaps
- [ ] Material swaps

---

# Milestone C: Weapon System Expansion

## Weapon Slots

- [ ] Add primary weapon slot
- [ ] Add melee weapon slot
- [ ] Add gadget slot

## New Weapons

### Suction-Dart Crossbow

- [ ] Implement weapon
- [ ] Add piercing mechanic
- [ ] Create upgrade path

### Confetti Cannon

- [ ] Implement weapon
- [ ] Add area damage mechanic
- [ ] Create upgrade path

### Stink Bomb

- [ ] Implement weapon
- [ ] Make riders swerve
- [ ] Create upgrade path

### Phone Launcher

- [ ] Implement weapon
- [ ] Create upgrade path

## Synergies

- [ ] Create perk interactions
- [ ] Create duo synergies with existing perk system

---

# Milestone D: Run Map, Relics & Modifiers

## Run Structure

- [ ] Replace linear round progression

### Map Nodes

- [ ] Normal encounter
- [ ] Elite encounter
- [ ] Shop
- [ ] Event
- [ ] Rest stop
- [ ] Boss node

## Relics

- [ ] Implement relic system
- [ ] Add rule-changing relic effects

## Curses

- [ ] Add risk/reward curse system

## Round Modifiers

- [ ] Night modifier
- [ ] Rain modifier
- [ ] Double riders modifier
- [ ] Additional modifier ideas

## New Arenas

- [ ] Bridge arena
- [ ] Market arena
- [ ] Tunnel arena

---

# Milestone E: Polish & Accessibility

## Dynamic Presentation

- [ ] Dynamic music system
- [ ] Scale intensity with style rank

## Onboarding

- [ ] Short tutorial
- [ ] Key rebinding

## Accessibility

- [ ] Subtitle support for voice lines
- [ ] Colourblind-safe telegraphs
- [ ] English localization
- [ ] Slovenian localization review

## Release Readiness

- [ ] Create app icon
- [ ] Add credits screen
- [ ] Configure Windows export presets

---

# Technical Refactor (Recommended Before Milestone D)

## Code Structure

- [ ] Break up `main.gd` (~3,600 lines)
- [ ] Move systems into dedicated modules

## Data-Driven Content

- [ ] Move items into data tables
- [ ] Move perks into data tables
- [ ] Move weapons into data tables

## Future-Proofing

- [ ] Make weapon additions easier
- [ ] Make relic additions easier
- [ ] Prepare architecture for potential co-op support

---

# Suggested Development Order

- [ ] Milestone A: Menu, game flow, saves, high scores
- [ ] Milestone B: Meta currency, unlocks, skins
- [ ] Milestone C: Weapon slots and new weapons
- [ ] Milestone D: Run map, relics, modifiers
- [ ] Milestone E: Polish, tutorial, music