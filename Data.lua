local _, ns = ...

-- Same CVars Blizzard's Audio options panel uses. Labels are the game's own localized strings.
ns.CHANNELS = {
    { vol = "Sound_MasterVolume",   on = "Sound_EnableAllSound", label = MASTER_VOLUME },
    { vol = "Sound_MusicVolume",    on = "Sound_EnableMusic",    label = MUSIC_VOLUME },
    { vol = "Sound_SFXVolume",      on = "Sound_EnableSFX",      label = FX_VOLUME },
    { vol = "Sound_AmbienceVolume", on = "Sound_EnableAmbience", label = AMBIENCE_VOLUME },
    { vol = "Sound_DialogVolume",   on = "Sound_EnableDialog",   label = DIALOG_VOLUME },
}

-- Preset format: volumes in percent, in CHANNELS order; `on` is a bitmask of enabled channels
-- (bit 1 = first channel).
local ALL_ON = 2 ^ #ns.CHANNELS - 1

ns.DEFAULT_PRESETS = {
    ["Music focus"]   = { 100, 100, 30, 40, 60, on = ALL_ON },
    ["Effects focus"] = { 100, 20, 100, 60, 100, on = ALL_ON },
    ["Quiet"]         = { 30, 30, 30, 30, 30, on = ALL_ON },
    -- Only the Master toggle goes off, so any other preset brings sound straight back.
    ["Mute"]          = { 100, 100, 100, 100, 100, on = ALL_ON - 1 },
    -- Like EzFishing's session: effects at full so the bobber splash stands out, everything else off.
    ["Fishing"]       = { 100, 50, 100, 50, 100, on = 1 + 4 }, -- only Master and Effects on
}
