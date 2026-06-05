local ADDON_NAME, ns = ...

ns.Keybinds = {}
local KB = ns.Keybinds

-- Keybindings "follow the bar": a key is bound to a POSITION (reading order over
-- the visible buttons), not to a fixed slot. When hidden talents/role swaps
-- collapse the row, position N just points at whatever button now sits there.
--
-- The cast itself is fired by WoW's secure "CLICK <frame>:<button>" override
-- binding: pressing the key makes the engine click the named secure button, so
-- the macro casts with full security and works in combat. The bindings can only
-- be (re)applied OUT of combat (SetOverrideBindingClick is combat-protected), so
-- AB:Relayout (which already no-ops in combat and re-runs on PLAYER_REGEN_ENABLED)
-- is where we refresh them.

-- A dedicated owner frame so ClearOverrideBindings only wipes OUR bindings.
local owner = CreateFrame("Frame", "HelloWarrior_BindOwner")

-- Defaults: number row 1..7 for the top row, then Shift+ for the rows beneath
-- it -- Shift+1..7, continuing onto Shift+8/9/0/-/= so the bottom row is covered
-- too. (Positions are a flat reading-order list; rows differ in width by role,
-- so this spans both the dps and tank bottom rows.) The shouts row and anything
-- past these stay unbound until assigned. Stored per-character.
local function defaults()
    return {
        ability = {
            "1", "2", "3", "4", "5", "6", "7",
            "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "SHIFT-5", "SHIFT-6", "SHIFT-7",
            "SHIFT-8", "SHIFT-9", "SHIFT-0", "SHIFT--", "SHIFT-=",
        },
        -- Bottom row (ranged, shouts, then racials) on Alt+1..8.
        shout = {
            "ALT-1", "ALT-2", "ALT-3", "ALT-4", "ALT-5", "ALT-6", "ALT-7", "ALT-8",
        },
    }
end

-- ---------- helpers --------------------------------------------------------

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

-- Build WoW's binding string ("ALT-CTRL-SHIFT-KEY" order) from a base key plus
-- the modifiers currently held. Returns nil for a bare modifier press.
local function chord(key)
    if not key or MODIFIER_KEYS[key] then return nil end
    local s = ""
    if IsAltKeyDown() then s = s .. "ALT-" end
    if IsControlKeyDown() then s = s .. "CTRL-" end
    if IsShiftKeyDown() then s = s .. "SHIFT-" end
    return s .. key
end

-- Compact label for the on-button hotkey text (e.g. "SHIFT-E" -> "sE").
local function shortKey(key)
    if not key or key == "" then return "" end
    return (key
        :gsub("ALT%-", "a")
        :gsub("CTRL%-", "c")
        :gsub("SHIFT%-", "s")
        :gsub("BUTTON", "m")
        :gsub("MOUSEWHEELUP", "mwu")
        :gsub("MOUSEWHEELDOWN", "mwd")
        :gsub("NUMPAD", "n"))
end

local function mouseFocus()
    if GetMouseFoci then
        local t = GetMouseFoci()
        return t and t[1]
    end
    if GetMouseFocus then return GetMouseFocus() end
end

-- Visible ability buttons in reading order (= slot order; rows are contiguous
-- slices of slot order, so filtering shown buttons reproduces the layout order).
local function orderedAbility(AB)
    local t = {}
    if AB.buttons then
        for _, b in ipairs(AB.buttons) do
            if b:IsShown() then t[#t + 1] = b end
        end
    end
    return t
end

-- Bottom row in reading order: ranged button first (when shown), then shouts,
-- then the player's race racials (racials live in self.shoutButtons too).
local function orderedShout(AB)
    local t = {}
    if AB.rangedButton and AB.rangedButton:IsShown() then t[#t + 1] = AB.rangedButton end
    for _, b in ipairs(AB.shoutButtons or {}) do
        if b:IsShown() then t[#t + 1] = b end
    end
    return t
end

local function eachList(kb, fn)
    fn(kb.ability)
    fn(kb.shout)
end

-- Drop `key` from every position so a key only ever maps to one button.
local function removeKey(kb, key)
    eachList(kb, function(list)
        for pos, k in pairs(list) do
            if k == key then list[pos] = nil end
        end
    end)
end

-- ---------- apply / labels -------------------------------------------------

function KB:Apply()
    if not ns.enabled then return end
    local AB = ns.ActionBar
    if not AB or not AB.buttons then return end
    if InCombatLockdown() then return end  -- re-runs from Relayout on regen

    ClearOverrideBindings(owner)
    -- Bars hidden -> no keybind overrides either: clear them (above) and don't
    -- re-apply, so the keys fall back to their normal action while the bars are
    -- off. AB:SetHWBarsVisible calls Apply when toggling.
    if HelloWarriorCharDB.showHWBars == false then return end

    local kb = HelloWarriorCharDB.keybinds
    if not kb then return end

    local function bind(list, ordered)
        for pos, key in pairs(list) do
            local btn = ordered[pos]
            if btn and key and key ~= "" then
                SetOverrideBindingClick(owner, true, key, btn:GetName(), "LeftButton")
            end
        end
    end
    bind(kb.ability, orderedAbility(AB))
    bind(kb.shout, orderedShout(AB))
end

function KB:SetLabel(btn, key)
    if not btn._hwKeyLabel then
        local fs = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        fs:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
        fs:SetJustifyH("RIGHT")
        btn._hwKeyLabel = fs
    end
    btn._hwKeyLabel:SetText(key and shortKey(key) or "")
end

-- Paint each visible button with the hotkey for its current position; clear the
-- text on hidden buttons so a collapsed slot doesn't show a stale key.
function KB:RefreshLabels()
    local AB = ns.ActionBar
    if not AB or not AB.buttons then return end
    local kb = HelloWarriorCharDB.keybinds

    local ao = orderedAbility(AB)
    for pos, b in ipairs(ao) do self:SetLabel(b, kb and kb.ability[pos]) end
    local so = orderedShout(AB)
    for pos, b in ipairs(so) do self:SetLabel(b, kb and kb.shout[pos]) end

    for _, b in ipairs(AB.buttons) do
        if not b:IsShown() then self:SetLabel(b, nil) end
    end
    for _, b in ipairs(AB.shoutButtons or {}) do
        if not b:IsShown() then self:SetLabel(b, nil) end
    end
end

-- ---------- editing --------------------------------------------------------

function KB:Assign(kind, pos, key)
    local kb = HelloWarriorCharDB.keybinds
    removeKey(kb, key)
    kb[kind][pos] = key
    self:Apply()
    self:RefreshLabels()
    print(("|cffc79c6eHelloWarrior|r bound %s to %s slot %d"):format(key, kind, pos))
end

function KB:Clear(kind, pos)
    local kb = HelloWarriorCharDB.keybinds
    kb[kind][pos] = nil
    self:Apply()
    self:RefreshLabels()
end

function KB:ClearAll()
    HelloWarriorCharDB.keybinds = { ability = {}, shout = {} }
    self:Apply()
    self:RefreshLabels()
    print("|cffc79c6eHelloWarrior|r keybindings cleared.")
end

function KB:ResetDefaults()
    HelloWarriorCharDB.keybinds = defaults()
    self:Apply()
    self:RefreshLabels()
    print("|cffc79c6eHelloWarrior|r keybindings reset to defaults.")
end

-- ---------- keybind mode ---------------------------------------------------

function KB:TargetUnderMouse()
    local AB = ns.ActionBar
    if not AB then return end
    local f = mouseFocus()
    if not f then return end
    for pos, b in ipairs(orderedAbility(AB)) do
        if b == f then return "ability", pos end
    end
    for pos, b in ipairs(orderedShout(AB)) do
        if b == f then return "shout", pos end
    end
end

function KB:OnKey(key)
    if key == "ESCAPE" then self:ExitMode(); return end
    local kind, pos = self:TargetUnderMouse()
    if not kind then return end
    if key == "DELETE" or key == "BACKSPACE" then
        self:Clear(kind, pos)
        return
    end
    local c = chord(key)
    if c then self:Assign(kind, pos, c) end
end

function KB:EnsureUI()
    if self.capture then return end
    -- 1x1, mouse-disabled frame: keyboard-enabled frames receive all key events
    -- regardless of size/focus, and disabling its mouse keeps GetMouseFocus on
    -- the actual button under the cursor.
    local cap = CreateFrame("Frame", nil, UIParent)
    cap:SetPoint("CENTER")
    cap:SetSize(1, 1)
    cap:SetFrameStrata("FULLSCREEN_DIALOG")
    cap:EnableKeyboard(false)
    cap:SetPropagateKeyboardInput(false)  -- swallow keys while binding
    cap:Hide()
    cap:SetScript("OnKeyDown", function(_, key) KB:OnKey(key) end)
    self.capture = cap

    local banner = cap:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner:SetPoint("TOP", UIParent, "TOP", 0, -140)
    banner:SetJustifyH("CENTER")
    banner:SetText("HelloWarrior keybind mode\n" ..
        "Hover a button and press a key to bind it.  Delete clears.  Esc exits.")
    banner:Hide()
    self.banner = banner
end

function KB:EnterMode()
    if not ns.enabled then return end
    local AB = ns.ActionBar
    if not AB or not AB.buttons then return end
    if HelloWarriorCharDB.showHWBars == false then
        print("|cffc79c6eHelloWarrior|r turn the bars on first (/hw bars on) to edit keybindings.")
        return
    end
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't edit keybindings in combat.")
        return
    end
    self.mode = true
    self:EnsureUI()
    self.capture:EnableKeyboard(true)
    self.capture:Show()
    self.banner:Show()
    self:RefreshLabels()
    print("|cffc79c6eHelloWarrior|r keybind mode: hover a button, press a key. Delete clears, Esc exits.")
end

function KB:ExitMode()
    self.mode = false
    if self.capture then
        self.capture:EnableKeyboard(false)
        self.capture:Hide()
    end
    if self.banner then self.banner:Hide() end
    self:Apply()
end

function KB:ToggleMode()
    if self.mode then self:ExitMode() else self:EnterMode() end
end

-- Seed per-character defaults once (ADDON_LOADED runs after Core's Config:Init,
-- so HelloWarriorCharDB already exists). Only when absent, so cleared bindings
-- aren't silently re-added on the next login.
ns:On("ADDON_LOADED", function(name)
    if name ~= ns.ADDON_NAME then return end
    if HelloWarriorCharDB.keybinds == nil then
        HelloWarriorCharDB.keybinds = defaults()
    end
end)

-- Force-exit keybind mode the instant combat starts. The capture frame runs
-- SetPropagateKeyboardInput(false), so it swallows ALL keyboard input while up;
-- leaving it open in combat would eat movement and ability keys until the
-- player thought to press Esc. ExitMode's own Apply() is a no-op in combat, and
-- the override bindings applied before the fight stay live, so this is safe.
ns:On("PLAYER_REGEN_DISABLED", function()
    if KB.mode then
        KB:ExitMode()
        print("|cffc79c6eHelloWarrior|r keybind mode closed (entered combat).")
    end
end)
