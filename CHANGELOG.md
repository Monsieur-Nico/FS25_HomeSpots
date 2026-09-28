# Changelog

All notable changes to Home Spots are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use the four-part
Farming Simulator scheme `major.minor.patch.build`, matching `<version>` in `modDesc.xml`.

## [Unreleased]

## [1.1.0.9] - 2026-09-28

### Added
- "Send home" in the map menu of a selected vehicle or tool (next to Enter vehicle, Reset and Sell). It shows
  when the vehicle, or a tool attached to it, has a home spot and is away from it.

### Fixed
- On foot, standing inside or right next to a vehicle's outline (for example between a tractor and its seeder)
  no longer locks the prompts onto that vehicle wherever you look.
- The prompts no longer freeze on one vehicle after getting in and out of it. The keys were registered on foot
  and in the vehicle under the same ids, so updates only reached the in-vehicle copy.

### Changed
- Map markers show only spots whose vehicle is away, as an orange badge, so parked vehicles no longer
  have a house stacked under their own map icon. A new "Home spot markers" setting offers Away only (default),
  Always (green when home, orange when away) or Off, saved with the savegame.

## [1.1.0.8] - 2026-09-28

### Added
- Alt + U sends only what you sit in, or the tool or vehicle you look at, to its home spot. Sitting in it,
  you ride along; a tool looked at on foot is unhooked from whatever pulls it. The help panel shows
  "Send home: <name>" whenever the target has a home spot.
- One in-game hour before the daily tidy-up, a message says when vehicles go home, e.g. "Vehicles go home at 20:00".

### Changed
- The mod icon is 512 × 512 and DXT1, the map marker DXT5, as the GIANTS TestRunner requires.
- `modDesc.xml` uses descVersion 113 and its description ends with a changelog.
- The title is "Home Spots" in French too (falls back to the English title).
- Errors are no longer caught and hidden; they show in `log.txt` with the game's own stack trace.

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

[Unreleased]: https://github.com/Monsieur-Nico/FS25_HomeSpots/compare/v1.1.0.9...HEAD
[1.1.0.9]: https://github.com/Monsieur-Nico/FS25_HomeSpots/compare/v1.1.0.8...v1.1.0.9
[1.1.0.8]: https://github.com/Monsieur-Nico/FS25_HomeSpots/compare/v1.1.0.7...v1.1.0.8
[1.1.0.7]: https://github.com/Monsieur-Nico/FS25_HomeSpots/releases/tag/v1.1.0.7
