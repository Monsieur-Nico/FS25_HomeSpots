# Changelog

All notable changes to Home Spots are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use the four-part
Farming Simulator scheme `major.minor.patch.build`, matching `<version>` in `modDesc.xml`.

## [Unreleased]

## [1.1.0.7] - 2026-09-28

### Added
- The help panel names what a key will act on, for example "Set home spot: Horsch Finer 6 SL",
  and saved or removed messages name the vehicles too.
- Sending vehicles home skips anything already within 1 m and 10° of its spot and reports it as already home.
- Setting a spot on foot also finds tools with open frames, such as seed drills, up to 6 m away.
- `log.txt` notes how many home spots were loaded and saved.

### Fixed
- The set and remove prompts no longer stay in the help panel after looking away.
- The tidy-up setting is a proper hour picker (Off, 00:00 to 23:00) instead of an on/off toggle.
- Loading a savegame with saved spots no longer fails, which had also broken the in-game map screen
  and emptied the saved spots on the next save.
- The game no longer freezes from an error in the help panel update.
- Map markers can be clicked on the in-game map.

## [1.1.0.0] - 2026-09-28

### Added
- A vehicle whose home spot is taken stays where it is, and the message says which one.
- Set or remove a spot on foot by looking at a vehicle or tool.
- House markers on the in-game map for every saved spot.
- Daily tidy-up: pick an hour in the settings menu to send everything home automatically.

## [1.0.0.1] - 2026-09-28

### Changed
- All Home Spots keys are shown in the help panel.

## [1.0.0.0] - 2026-09-28

### Added
- Save a home spot for a vehicle and its attached tools, and send every vehicle and tool home with one key.

[Unreleased]: https://github.com/Monsieur-Nico/FS25_HomeSpots/compare/v1.1.0.7...HEAD
[1.1.0.7]: https://github.com/Monsieur-Nico/FS25_HomeSpots/releases/tag/v1.1.0.7
