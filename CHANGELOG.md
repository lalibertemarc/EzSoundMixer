# EzSoundMixer

## v1.2.0

- Right-click EzSoundMixer in the addon menu on the minimap to pick a preset, same as right-clicking the minimap button, so presets stay handy with the button hidden.
- Hide the minimap button with Shift-click, or with the new "Show minimap button" checkbox in the mixer panel. `/ezsm minimap` still works too.

## v1.1.1

- Fix a game crash when opening the presets list in combat (right-clicking the minimap button). The presets list is now EzSoundMixer's own popup instead of the game's menus, so it works in combat.
- Fix the panel's close (X) button doing nothing in combat.

## v1.1.0

- New default preset: Mute turns off all sound (Master off). Handy as a macro: `/ezsm Mute`.

## v1.0.0

- First release for WoW Forever.
- Small mixer panel with Master, Music, Effects, Ambience and Dialog sliders, each with an on/off checkbox. Stays in sync with the game's Audio options.
- Open it from the minimap button, the addon menu on the minimap, or `/ezsm`. Right-click the minimap button to pick a preset without opening the panel. Drag it to move it; `/ezsm minimap` hides or shows it.
- Save the current volumes as a named preset, pick presets from a dropdown, delete ones you don't need. Comes with Music focus, Effects focus, Quiet and Fishing (effects at full, music, ambience and dialog off, like EzFishing).
- `/ezsm <preset>` applies a preset without opening the panel, so presets work in macros.
