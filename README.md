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
- **Never stacks vehicles.** If something else is parked on a spot, or a building or tree now stands in it, that
  vehicle stays where it is and you are told which one.
- **Park in a shed.** One key finds a free place under the roof of your nearest shed, clear of walls, posts, pallets
  and other vehicles, saves it as the home spot and sends the vehicle there, facing out of the open side.
- **Leaves things alone.** Vehicles you or a worker are driving stay put, and anything already on its spot is not moved.
- **Map markers.** An orange house on the map marks every spot whose vehicle is away, so a tidy farm shows none.
  In the settings you can show every spot instead, green while its vehicle is home, or turn markers off.
- **Home Spots page.** A page in the game's menu lists every vehicle and tool with a spot: home, away or in use,
  and how far from its spot, with a count of each above the shop picture of the selected one and the tools
  that come along with it. Send it home, show it on the map, remove its spot, or send everything home.
- **Daily tidy-up.** Pick an hour in the settings menu, for example 20:00, and everything goes home by itself every day.
- **Realism fee.** Optionally pay for each vehicle sent home, per km of the way back, as if a worker had driven it.
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
| Alt + N | Park what you sit in or look at in a shed and make that its home spot |

On the map, select a vehicle or tool that is away from its spot and pick **Send home**.

In the menu (Esc), the **Home Spots** page lists your vehicles and tools with a spot. Select one that is away and
press **Send home**, or press **Send all vehicles home**.

All keys can be changed in the game's Controls menu.

## Settings

Open **Settings** from the pause menu and scroll to the bottom of the General page. Under **Home Spots**:

- **Send vehicles home at**: Off, or any hour from 00:00 to 23:00. A message warns you one in-game hour before.
- **Home spot markers**: Away only (default), Always (green when home, orange when away) or Off.
- **Realism fee**: Off (default), Low, Normal or High: 25, 50 or 100 per km of straight-line distance home,
  scaled by the economic difficulty like worker wages and booked as wages. Tools hooked to a vehicle that goes home
  ride along for free. If your farm can't pay, the vehicle stays put and you're told the price; the daily tidy-up
  always goes ahead. Normal is about what a base-game worker earns driving the same way home.

All three are saved with the savegame.

## Compatibility

- Farming Simulator 25 on PC.
- Single-player and multiplayer. In multiplayer every player shares the same spots and map markers,
  Alt + H and the map send home only your own farm's vehicles, and only the host or a server admin can
  change the Home Spots settings.
- No other mods are needed.
- Parking Spaces and other decorative parking lines work as they are: park on a space and press Alt + J.

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
