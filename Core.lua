-- EzSoundMixer: sound volume sliders and presets, one click away.
local addonName, ns = ...

local CHANNELS = ns.CHANNELS
local GetCVar, SetCVar = C_CVar.GetCVar, C_CVar.SetCVar
local floor, format = math.floor, string.format

local db          -- EzSoundMixerDB, set on ADDON_LOADED
local frame       -- the mixer panel; built the first time it's opened
local rows = {}
local selected    -- name of the preset the current volumes match, or nil
local refreshing  -- true while widgets are synced from CVars, so they don't write back
local SetMinimapHidden -- defined with the minimap button, used by the panel
local events = CreateFrame("Frame")

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99EzSoundMixer|r: " .. msg)
end

---------------------------------------------------------------------------
-- CVars and presets
---------------------------------------------------------------------------
local function Volume(ch) return tonumber(GetCVar(ch.vol)) or 0 end
local function Percent(ch) return floor(Volume(ch) * 100 + 0.5) end
local function IsOn(ch) return GetCVar(ch.on) == "1" end
local function SetVolume(ch, v) SetCVar(ch.vol, format("%.2f", v)) end
local function SetOn(ch, on) SetCVar(ch.on, on and "1" or "0") end

-- Bit i of a preset's `on` mask is channel i's enable toggle.
local function Flag(i) return 2 ^ (i - 1) end
local function HasFlag(mask, i) return floor(mask / Flag(i)) % 2 == 1 end

local function Capture()
    local p = { on = 0 }
    for i, ch in ipairs(CHANNELS) do
        p[i] = Percent(ch)
        if IsOn(ch) then p.on = p.on + Flag(i) end
    end
    return p
end

local function Matches(p)
    for i, ch in ipairs(CHANNELS) do
        if p[i] ~= Percent(ch) or HasFlag(p.on, i) ~= IsOn(ch) then return false end
    end
    return true
end

local function Apply(p)
    for i, ch in ipairs(CHANNELS) do
        SetVolume(ch, p[i] / 100)
        SetOn(ch, HasFlag(p.on, i))
    end
end

-- Defaults live in Data.lua, not the saved variables, so changes to them always show up.
-- A saved preset with the same name wins; deleted defaults are listed in db.hidden.
local DEFAULTS = ns.DEFAULT_PRESETS

local function GetPreset(name)
    return db.presets[name] or (not db.hidden[name] and DEFAULTS[name]) or nil
end

local function PresetNames()
    local names = {}
    for name in pairs(DEFAULTS) do
        if GetPreset(name) then names[#names + 1] = name end
    end
    for name in pairs(db.presets) do
        if not DEFAULTS[name] then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

---------------------------------------------------------------------------
-- Panel state
---------------------------------------------------------------------------
local function SetSelected(name)
    selected = name
    if frame then
        frame.presets:SetText(name or "Presets")
        frame.delete:SetEnabled(name ~= nil)
    end
end

-- Drop the preset selection once the volumes no longer match it.
local function CheckSelected()
    local p = selected and GetPreset(selected)
    if selected and not (p and Matches(p)) then SetSelected(nil) end
end

local function Refresh()
    if not (frame and frame:IsShown()) then return end
    refreshing = true
    local masterOn = IsOn(CHANNELS[1])
    for i, row in ipairs(rows) do
        local active = i == 1 or masterOn
        local on = IsOn(row.ch)
        row.check:SetChecked(on)
        row.check:SetEnabled(active)
        row.check.Text:SetTextColor((active and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
        row.slider:SetValue(Volume(row.ch))
        row.slider:SetEnabled(active and on)
    end
    frame.minimap:SetChecked(not db.minimapHidden)
    refreshing = false
    CheckSelected()
end

local function ApplyPreset(name)
    Apply(GetPreset(name))
    SetSelected(name)
    Refresh()
end

local function SavePreset(name, confirmed)
    name = strtrim(name or "")
    if name == "" then return end
    if GetPreset(name) and not confirmed then
        StaticPopup_Show("EZSOUNDMIXER_OVERWRITE", name, nil, name)
        return
    end
    db.presets[name] = Capture()
    db.hidden[name] = nil
    SetSelected(name)
end

local function DeletePreset(name)
    db.presets[name] = nil
    if DEFAULTS[name] then db.hidden[name] = true end
    if selected == name then SetSelected(nil) end
end

---------------------------------------------------------------------------
-- Preset list: a popup of our own rather than Blizzard's menu system, which
-- crashes the client when an addon opens a menu in combat.
---------------------------------------------------------------------------
local list        -- built the first time it's opened
local listRows = {}
local ROW_HEIGHT, CHECK_WIDTH = 18, 18

local function ListRow(i)
    if listRows[i] then return listRows[i] end
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, -8 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", -10, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    row.check:SetSize(16, 16)
    row.check:SetPoint("LEFT")
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("LEFT", CHECK_WIDTH, 0)
    row:SetScript("OnClick", function(self)
        list:Hide()
        ApplyPreset(self.name)
    end)
    listRows[i] = row
    return row
end

local function FillList()
    local names = PresetNames()
    local count, width = math.max(#names, 1), 0
    for i = 1, count do
        local row, name = ListRow(i), names[i]
        row.name = name
        row.text:SetText(name or "No presets saved")
        row.text:SetTextColor((name and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR):GetRGB())
        row.check:SetShown(name ~= nil and name == selected)
        row:SetEnabled(name ~= nil)
        row:Show()
        width = math.max(width, row.text:GetStringWidth())
    end
    for i = count + 1, #listRows do listRows[i]:Hide() end
    list:SetSize(width + CHECK_WIDTH + 24, count * ROW_HEIGHT + 16)
end

local function BuildList()
    list = CreateFrame("Frame", "EzSoundMixerPresetList", UIParent, "TooltipBackdropTemplate")
    list:Hide()
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    tinsert(UISpecialFrames, list:GetName()) -- Esc closes it

    -- A click anywhere else closes it; only listen while it's open.
    list:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    list:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    list:SetScript("OnEvent", function(self)
        -- Clicks on the owner are left to its OnClick, which toggles the list.
        if not (self:IsMouseOver() or self.owner:IsMouseOver()) then self:Hide() end
    end)
end

-- Opens the list with its `point` on the owner's `relPoint`, or closes it if the owner already has it open.
local function ToggleList(owner, point, relPoint)
    if list and list:IsShown() and list.owner == owner then
        list:Hide()
        return
    end
    if not list then BuildList() end
    list.owner = owner
    FillList()
    list:ClearAllPoints()
    list:SetPoint(point, owner, relPoint)
    list:Show()
end

---------------------------------------------------------------------------
-- UI (built lazily)
---------------------------------------------------------------------------
local function Dialog(which, t)
    t.timeout, t.whileDead, t.hideOnEscape = 0, 1, 1
    StaticPopupDialogs[which] = t
end

-- Yes/no dialog; the preset name is both the text argument and the data.
local function Confirm(which, text, button1, onAccept)
    Dialog(which, {
        text = text,
        button1 = button1,
        button2 = CANCEL,
        OnAccept = function(_, name) onAccept(name, true) end,
    })
end

local function SaveFromDialog(dialog)
    SavePreset(dialog:GetEditBox():GetText())
end

local function CreateDialogs()
    Dialog("EZSOUNDMIXER_SAVE", {
        text = "Save current volumes as:",
        button1 = SAVE,
        button2 = CANCEL,
        hasEditBox = 1,
        maxLetters = 32,
        OnShow = function(dialog)
            local editBox = dialog:GetEditBox()
            editBox:SetText(selected or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end,
        OnAccept = SaveFromDialog,
        EditBoxOnEnterPressed = function(editBox)
            local dialog = editBox:GetParent()
            SaveFromDialog(dialog)
            dialog:Hide()
        end,
        EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
    })
    Confirm("EZSOUNDMIXER_OVERWRITE", 'Replace preset "%s"?', YES, SavePreset)
    Confirm("EZSOUNDMIXER_DELETE", 'Delete preset "%s"?', DELETE, DeletePreset)
end

local function Button(text, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(72, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function SavePosition(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.pos = { point, relPoint, x, y }
end

local function Build()
    frame = CreateFrame("Frame", "EzSoundMixerFrame", UIParent, "DefaultPanelFlatTemplate")
    frame:Hide()
    frame:SetSize(370, 268)
    frame:SetTitle("Sound Mixer")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", SavePosition)
    local pos = db.pos or { "CENTER", "CENTER", 0, 0 }
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    tinsert(UISpecialFrames, frame:GetName()) -- Esc closes it

    -- Only listen for CVar changes while the panel is visible.
    frame:SetScript("OnShow", function()
        events:RegisterEvent("CVAR_UPDATE")
        Refresh()
    end)
    frame:SetScript("OnHide", function()
        events:UnregisterEvent("CVAR_UPDATE")
        if list and list.owner == frame.presets then list:Hide() end
    end)

    -- The template's own OnClick goes through HideUIPanel, which is blocked in combat.
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")
    close:SetScript("OnClick", function() frame:Hide() end)

    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return FormatPercentage(v, true) end,
    }
    for i, ch in ipairs(CHANNELS) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", 14, -32 - (i - 1) * 32)
        check.Text:SetFontObject(GameFontHighlight)
        check.Text:SetText(ch.label)
        check:SetScript("OnClick", function(self)
            SetOn(ch, self:GetChecked())
            Refresh()
        end)

        local slider = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
        slider:SetSize(180, 26)
        slider:SetPoint("LEFT", check, "LEFT", 132, 0)
        slider:Init(Volume(ch), 0, 1, 20, formatters)
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            if refreshing then return end
            SetVolume(ch, value)
            CheckSelected()
        end, slider)

        rows[i] = { ch = ch, check = check, slider = slider }
    end

    frame.minimap = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.minimap:SetSize(26, 26)
    frame.minimap:SetPoint("TOPLEFT", 14, -32 - #CHANNELS * 32)
    frame.minimap.Text:SetFontObject(GameFontHighlight)
    frame.minimap.Text:SetText("Show minimap button")
    frame.minimap:SetScript("OnClick", function(self) SetMinimapHidden(not self:GetChecked()) end)

    frame.delete = Button(DELETE, function()
        if selected then StaticPopup_Show("EZSOUNDMIXER_DELETE", selected, nil, selected) end
    end)
    frame.delete:SetPoint("BOTTOMRIGHT", -14, 14)

    local save = Button(SAVE, function() StaticPopup_Show("EZSOUNDMIXER_SAVE") end)
    save:SetPoint("RIGHT", frame.delete, "LEFT", -6, 0)

    frame.presets = Button("Presets", function(self) ToggleList(self, "TOPLEFT", "BOTTOMLEFT") end)
    frame.presets:SetPoint("BOTTOMLEFT", 16, 14)
    frame.presets:SetPoint("RIGHT", save, "LEFT", -10, 0)
    local label = frame.presets:GetFontString() -- long preset names get cut with "..."
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    label:SetWordWrap(false)

    CreateDialogs()
    SetSelected(selected)
end

---------------------------------------------------------------------------
-- Minimap button: left-click opens the mixer, right-click lists presets, shift-click hides it,
-- drag to move
---------------------------------------------------------------------------
local minimapButton

local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 225)
    local radius = Minimap:GetWidth() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    PlaceMinimapButton()
end

local function ButtonTexture(layer, file, size, x, y)
    local t = minimapButton:CreateTexture(nil, layer)
    t:SetTexture(file)
    t:SetSize(size, size)
    t:SetPoint("TOPLEFT", x, y)
    return t
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "EzSoundMixerMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    ButtonTexture("BACKGROUND", "Interface\\Minimap\\UI-Minimap-Background", 20, 7, -5)
    local icon = ButtonTexture("ARTWORK", C_AddOns.GetAddOnMetadata(addonName, "IconTexture"), 17, 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) -- trim the icon's built-in border
    ButtonTexture("OVERLAY", "Interface\\Minimap\\MiniMap-TrackingBorder", 53, 0, 0)

    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ToggleList(self, "TOPRIGHT", "BOTTOMLEFT")
        elseif IsShiftKeyDown() then
            SetMinimapHidden(true)
        else
            EzSoundMixer_Toggle()
        end
    end)

    -- Track the cursor only while dragging.
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(addonName)
        GameTooltip:AddLine("Left-click: open the mixer", 1, 1, 1)
        GameTooltip:AddLine("Right-click: presets", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: hide this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    PlaceMinimapButton()
end

-- Built only when shown, so players who hide it don't pay for it.
local function UpdateMinimapButton()
    if not db.minimapHidden and not minimapButton then CreateMinimapButton() end
    if minimapButton then minimapButton:SetShown(not db.minimapHidden) end
end

function SetMinimapHidden(hidden)
    db.minimapHidden = hidden
    UpdateMinimapButton()
    if hidden and (list and list.owner == minimapButton) then list:Hide() end
    Refresh()
    Print(hidden and "Minimap button hidden. Bring it back from the mixer panel or with /ezsm minimap." or "Minimap button shown.")
end

---------------------------------------------------------------------------
-- Events, entry points
---------------------------------------------------------------------------
local function OnAddonLoaded()
    EzSoundMixerDB = EzSoundMixerDB or {}
    db = EzSoundMixerDB
    db.presets = db.presets or {}
    db.hidden = db.hidden or {}
    UpdateMinimapButton()
    -- Pick up a preset the volumes already match, so the panel opens with it selected.
    for _, name in ipairs(PresetNames()) do
        if Matches(GetPreset(name)) then selected = name break end
    end
end

events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "CVAR_UPDATE" then
        if arg1 and arg1:lower():find("^sound_") then Refresh() end
    elseif arg1 == addonName then
        self:UnregisterEvent("ADDON_LOADED")
        OnAddonLoaded()
    end
end)

function EzSoundMixer_Toggle()
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

-- Addon drawer on the minimap (AddonCompartmentFunc): same clicks as the minimap button,
-- so presets stay one click away with the button hidden.
function EzSoundMixer_OnCompartmentClick(_, button)
    if button == "RightButton" then
        ToggleList(AddonCompartmentFrame, "TOPRIGHT", "BOTTOMLEFT")
    else
        EzSoundMixer_Toggle()
    end
end

function EzSoundMixer_OnCompartmentEnter(_, row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(addonName)
    GameTooltip:AddLine("Left-click: open the mixer", 1, 1, 1)
    GameTooltip:AddLine("Right-click: presets", 1, 1, 1)
    GameTooltip:Show()
end

function EzSoundMixer_OnCompartmentLeave()
    GameTooltip:Hide()
end

SLASH_EZSOUNDMIXER1 = "/ezsm"
SLASH_EZSOUNDMIXER2 = "/ezsoundmixer"
SlashCmdList.EZSOUNDMIXER = function(msg)
    msg = strtrim(msg or "")
    if msg == "" then return EzSoundMixer_Toggle() end
    local want = msg:lower()
    if want == "minimap" then return SetMinimapHidden(not db.minimapHidden) end
    for _, name in ipairs(PresetNames()) do
        if name:lower() == want then
            ApplyPreset(name)
            Print(format("Applied %s.", name))
            return
        end
    end
    Print(format('No preset named "%s".', msg))
end
