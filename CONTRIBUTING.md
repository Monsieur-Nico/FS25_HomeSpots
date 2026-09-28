# Contributing to Home Spots

Thanks for helping out. Bug reports with a `log.txt` are the most useful thing you can send.

## Reporting a bug

Open an issue with the bug report form. Attach `log.txt` from `Documents/My Games/FarmingSimulator2025`
straight after the problem happens: the game overwrites it every time it starts.

## Working on the code

The repository root is the mod folder, so you can clone it straight into your mods folder while working on it.
Remove any `FS25_HomeSpots.zip` from the mods folder first, so the game does not load two copies.

```
git clone https://github.com/Monsieur-Nico/FS25_HomeSpots.git "%USERPROFILE%/Documents/My Games/FarmingSimulator2025/mods/FS25_HomeSpots"
```

### Checks

The same checks run on every push and pull request. Run them locally with Lua 5.1, luacheck and xmllint:

```
luacheck scripts tests
xmllint --noout modDesc.xml
lua5.1 tests/run.lua
bash tools/build.sh
```

The tests replace the game with small stand-ins in `tests/game_mock.lua`. Only add stand-ins for functions that
exist in the real game (check the [FS25 script documentation](https://github.com/umbraprior/FS25-Community-LUADOC)),
otherwise a test can pass while the mod fails in game.

### Code style

- Lua 5.1, 4 spaces, one class per file in `scripts/`, each function with a `---` doc comment.
- Anything that runs every frame or from a game hook goes through `HomeSpots.runSafely`,
  so a mistake is logged once instead of breaking the game.
- Player-facing text lives in the `<l10n>` section of `modDesc.xml` in English, German and French.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `ci:`,
`refactor:` or `chore:`, followed by a short summary in the imperative, for example
`fix: hide the set prompt after looking away`.

## Releasing

1. Update `<version>` in `modDesc.xml`.
2. Move the "Unreleased" notes in `CHANGELOG.md` under a new version heading and add its compare link.
3. Commit and push, then either tag and push (`git tag v1.1.0.8 && git push origin v1.1.0.8`) or start the
   Release workflow from the Actions tab with "Run workflow", which creates the tag from the `modDesc.xml` version.

The release workflow checks that the tag matches `modDesc.xml`, runs the checks, builds `FS25_HomeSpots.zip`
and publishes it on the GitHub releases page with the changelog notes.
