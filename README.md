# Deck Mode for Farming Simulator 25

**Farming Simulator 25, made for handhelds.** Deck Mode makes FS25 comfortable on handheld PCs such as the Steam Deck: readable menus and HUD, handheld graphics presets and controller-first button hints, all adjustable in game.

## Features

### Bigger menu text

Scales the text in:

- the in-game menu (map, prices, finances, vehicles, settings opened from the pause menu, …)
- the shop
- dialogs and tooltips
- the button help bar at the bottom of the screen

The default is **200 %**. You can set it from 100 % to 200 %, live, in the settings menu.

### Handheld graphics presets

Choose a **target FPS** and a **graphics style**:

| | Power Saver | Balanced | High Quality |
|---|---|---|---|
| **30 FPS** | FSR 3 Performance, 60 % distances, no ambient occlusion | FSR 3 Balanced, 80 % distances, low ambient occlusion | FSR 3 Quality, 100 % distances, medium shadow distance and ambient occlusion, cloud shadows |
| **60 FPS** | FSR 3 Performance, 50 % distances | FSR 3 Performance, 70 % distances, low ambient occlusion | FSR 3 Balanced, 80 % distances, low ambient occlusion, cloud shadows |

All presets turn off soft shadows, foliage shadows, screen-space reflections and shadows, lens flares and mirrors. "Distances" means object, foliage, LOD, terrain LOD and foliage LOD distance. The target FPS sets the game's frame limit.

The presets are based on public tests: [SteamDeckHQ's Steam Deck review](https://steamdeckhq.com/game-reviews/farming-simulator-25/) (Medium + FSR 3 Quality at a 30 FPS cap ran a steady 30 FPS at 12–16 W) and [pcoptimizedsettings' per-setting costs](https://pcoptimizedsettings.com/farming-simulator-25-optimization-best-graphics-settings-for-fps-on-pc/) (mirrors, shadow quality, draw distances, foliage shadows and screen-space shadows cost the most). FS25 is often CPU-limited in towns and on big farms, so 60 FPS will not hold everywhere on a Steam Deck.

The default is **60 FPS, Balanced**. It is applied **once**, on the first savegame load with the mod, and saved like the settings menu saves graphics settings. Anything you change in the settings menu afterwards stays. Set Target FPS to **Off** if Deck Mode should not touch your graphics settings.

Steam Deck tip: leave the frame limit in the Steam performance overlay off (or at 60) and the refresh rate at 60 Hz, so the in-game frame limit decides.

### Bigger HUD

The game's own *UI Scale* setting for the HUD (speedometer, minimap, field info, …) stops at 125 %. Deck Mode's **HUD Size** goes up to 200 %; the default is **150 %**. Set it to *Game Setting* to use the game's own UI Scale again (do that before removing the mod).

### Controller mode

Turns gamepad input on and sets the button help to always show controller buttons, instead of switching to keyboard keys when you touch the screen or trackpad. Applied once on the first savegame load.

### In-game settings

Everything above can be changed in game: open the menu, go to **Settings → General settings**. The **DECK MODE** section at the top has:

- **Menu Text Size**: 100 % to 200 %, applied live.
- **HUD Size**: Game Setting, or 130 % to 200 %.
- **Target FPS**: Off, 30 FPS or 60 FPS.
- **Graphics Style**: Power Saver, Balanced or High Quality.
- **Controller Mode**: On or Off.

Graphics changes apply right away. To apply a preset again, switch to another value and back.

## What it does not change

- **The main menu** (career, save selection, mod selection). Farming Simulator only runs mod scripts once a savegame is loaded, so no mod can change the main menu.
- **Labels drawn directly on the map** (hotspot names). These are not scaled yet.
- **Steam Deck system settings** (TDP, Steam frame limiter, refresh rate). Mods cannot reach them.

## Install

1. Download `FS25_DeckMode.zip` from the [latest release](https://github.com/rennerdo30/FS25_DeckMode/releases/latest). Do not unpack it.
2. Put the zip into your mods folder:
   - Windows: `Documents/My Games/FarmingSimulator2025/mods/`
   - Steam Deck / Linux (Proton): `~/.local/share/Steam/steamapps/compatdata/2300320/pfx/drive_c/users/steamuser/Documents/My Games/FarmingSimulator2025/mods/`
3. Start the game and tick **Deck Mode** in the mod selection when you load your savegame.

When you update the mod, restart the game completely; it keeps the old zip loaded until then.

## Settings file

The mod stores its settings in `modSettings/FS25_DeckMode.xml` (next to the `mods` folder):

```xml
<deckMode scale="2.000000" hudScale="1.500000" targetFps="60" graphicsStyle="balanced" graphicsPresetApplied="true"
          controllerMode="true" controllerModeApplied="true"/>
```

- `scale`: text size, `1.0` to `2.0`.
- `hudScale`: HUD size, `0` (use the game's UI Scale) or `1.3` to `2.0`.
- `targetFps`: `off`, `30` or `60`.
- `graphicsStyle`: `powersaver`, `balanced` or `quality`.
- `graphicsPresetApplied` / `controllerModeApplied`: set back to `false` to apply again on the next savegame load.

The in-game settings section writes this file for you.

## How it works

Every piece of menu text in FS25 goes through the game's `TextElement` class. Deck Mode hooks the places where a text element gets its size (`loadProfile`, `loadFromXML`, `copyAttributes`) and multiplies it. Menus that the game built before the mod loaded are scaled once, in place. The minimum text size is left unchanged, so the game's own shrink-to-fit logic can still fit long texts into fixed-size boxes. Buttons that size themselves to their text (such as the settings tabs) take their background along.

Graphics presets call the same engine functions as the settings menu and save them the same way. The DECK MODE settings rows are clones of the game's own option rows, so they look native and work with touch, mouse and controller.

## Known issues

- At large text sizes, some fixed-size boxes may clip or overlap text. Please [open an issue](https://github.com/rennerdo30/FS25_DeckMode/issues) with a screenshot and the menu name.
- Multiplayer: every player needs the mod, as with any script mod. Graphics and text settings are local to each player.

## License

[MIT](LICENSE). Farming Simulator is a trademark of GIANTS Software; this is an unofficial fan mod. Steam Deck is a trademark of Valve Corporation.
