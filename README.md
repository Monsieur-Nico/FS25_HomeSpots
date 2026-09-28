# Home Spots for Farming Simulator 25

[![CI](https://github.com/Monsieur-Nico/FS25_HomeSpots/actions/workflows/ci.yml/badge.svg)](https://github.com/Monsieur-Nico/FS25_HomeSpots/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Monsieur-Nico/FS25_HomeSpots)](https://github.com/Monsieur-Nico/FS25_HomeSpots/releases/latest)

Give every vehicle and tool its own parking spot, then tidy up the whole farm with one key.

Park a tractor, a trailer or a seeder where it belongs and save that spot. When the day is done, press
**Alt + H** and everything goes back to where it lives: tools are unhooked and every machine is set down on its own
spot. You can also let the farm tidy itself up at a set time every day.

## Features

- **One key tidy-up.** Every vehicle and tool of your farm with a saved spot is sent home at once.
- **Save spots in a vehicle or on foot.** In a vehicle, the vehicle and everything hooked to it are saved together.
  On foot, look at a single tool or vehicle to save just that one.
- **Knows what you are looking at.** The help panel names the machine a key will act on, for example
  "Set home spot: Horsch Finer 6 SL".
- **Never stacks vehicles.** If something else is parked on a spot, that vehicle stays where it is and you are told
  which one.
- **Leaves things alone.** Vehicles you or a worker are driving stay put, and anything already on its spot is not moved.
- **Map markers.** Every saved spot shows as a small house on the in-game map.
- **Daily tidy-up.** Pick an hour in the settings menu, for example 20:00, and everything goes home by itself every day.
- **Saved with your savegame.** Spots and the tidy-up hour are stored in `homeSpots.xml` in the savegame folder.

## Installation

1. Download `FS25_HomeSpots.zip` from the [latest release](https://github.com/Monsieur-Nico/FS25_HomeSpots/releases/latest).
2. Close the game.
3. Put the zip, without unpacking it, in `Documents/My Games/FarmingSimulator2025/mods`.
   Remove any older `FS25_HomeSpots` zip or folder first.
4. Start the game and enable Home Spots for your savegame.

## Controls

| Key | Action |
| --- | --- |
| Alt + J | Set or update the home spot of what you sit in or look at |
| Alt + K | Remove the home spot of what you sit in or look at |
| Alt + H | Send every vehicle and tool home |
| Alt + U | Send only what you sit in or look at home |

All keys can be changed in the game's Controls menu.

## Settings

Open **Settings** from the pause menu and scroll to the bottom of the General page. Under **Home Spots**, choose
**Send vehicles home at**: Off, or any hour from 00:00 to 23:00. The choice is saved with the savegame.

## Compatibility

- Farming Simulator 25 on PC.
- Single-player. Multiplayer support is planned.
- No other mods are needed.

## Reporting problems

Please [open an issue](https://github.com/Monsieur-Nico/FS25_HomeSpots/issues/new/choose) and attach `log.txt` from
`Documents/My Games/FarmingSimulator2025`, taken right after the problem and before restarting the game.

## Development

The repository root is the mod folder. See [CONTRIBUTING.md](CONTRIBUTING.md) for the local checks, code style and
release steps.

```
scripts/        Mod source (one class per file)
tests/          Tests that run the mod against stand-ins for the game
tools/build.sh  Packages the mod into dist/FS25_HomeSpots.zip
modDesc.xml     Mod description, key bindings and translations
```

## License

See [LICENSE](LICENSE).
