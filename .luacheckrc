std = "lua51"
max_line_length = false
self = false

globals = {
    "EzSoundMixerDB",
    "EzSoundMixer_Toggle",
    "SLASH_EZSOUNDMIXER1",
    "SLASH_EZSOUNDMIXER2",
    "SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames",
}

read_globals = {
    -- Lua / WoW utility
    "strtrim", "tinsert",
    -- Frames & UI
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "GameFontHighlight", "GameTooltip",
    "Minimap", "GetCursorPosition",
    "HIGHLIGHT_FONT_COLOR", "GRAY_FONT_COLOR",
    "MinimalSliderWithSteppersMixin", "FormatPercentage",
    "StaticPopup_Show",
    -- Global strings
    "MASTER_VOLUME", "MUSIC_VOLUME", "FX_VOLUME", "AMBIENCE_VOLUME", "DIALOG_VOLUME",
    "SAVE", "DELETE", "CANCEL", "YES",
    -- Namespaced APIs
    "C_CVar", "C_AddOns",
}
