local ADDON_NAME, ns = ...

ns.ActionBar = {}
local AB = ns.ActionBar

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local ABILITIES_PER_ROW = 8
local ROW_GAP = 4
local SECTION_GAP = 10

-- Ranged-attack button. One macro fires whichever ranged weapon is equipped
-- via [worn:...] conditionals, so only the matching ability is cast. "!" keeps
-- the auto-repeat Shoot abilities firing instead of toggling off; Throw is a
-- single cast so it gets no "!". Works in every stance; no /startattack (that
-- starts melee auto-attack, the opposite of a ranged pull).
local RANGED_SLOT = 18  -- INVSLOT_RANGED
local RANGED_MACRO = "/cast [worn:Guns] !Shoot Gun; [worn:Bows] !Shoot Bow; [worn:Crossbows] !Shoot Crossbow; [worn:Thrown] Throw"
local RANGED_EMPTY_ICON = "Interface\\Icons\\Ability_Marksmanship"

-- ---------- helpers --------------------------------------------------------

local function stanceIdList(stance)
    if type(stance) == "string" then
        return tostring(ns.Abilities.STANCE_ID[stance])
    end
    local parts = {}
    for _, s in ipairs(stance) do
        table.insert(parts, tostring(ns.Abilities.STANCE_ID[s]))
    end
    return table.concat(parts, "/")
end

local function defaultStanceSpell(stance)
    if type(stance) == "string" then
        return ns.Abilities.STANCE_SPELL[ns.Abilities.STANCE_ID[stance]]
    end
    return ns.Abilities.STANCE_SPELL[ns.Abilities.STANCE_ID[stance[1]]]
end

local function primaryStanceId(stance)
    if not stance or stance == "any" then return nil end
    if type(stance) == "string" then return ns.Abilities.STANCE_ID[stance] end
    return ns.Abilities.STANCE_ID[stance[1]]
end

local function stanceMatches(stance)
    if not stance or stance == "any" then return true end
    local cur = GetShapeshiftForm()
    if type(stance) == "string" then return cur == ns.Abilities.STANCE_ID[stance] end
    for _, s in ipairs(stance) do
        if cur == ns.Abilities.STANCE_ID[s] then return true end
    end
    return false
end

-- DPS "hold Ctrl to switch to Berserker" applies to abilities usable in
-- Berserker that the macro doesn't already force there: "any"-stance abilities,
-- and multi-stance abilities that include Berserker. Berserker-only abilities
-- already dance there; battle/defensive-only ones can't be used in Berserker,
-- so Ctrl must not yank you out of the stance they need.
local function isBerserkerSwitchable(ability)
    local s = ability.stance
    if s == nil or s == "any" then return true end
    if type(s) == "table" then
        local hasBerserker, hasOther = false, false
        for _, v in ipairs(s) do
            if v == "berserker" then hasBerserker = true else hasOther = true end
        end
        return hasBerserker and hasOther
    end
    return false
end

local CTRL_BERSERKER_SWITCH = ("/cast [mod:ctrl,nostance:%d] %s"):format(
    ns.Abilities.STANCE_ID.berserker,
    ns.Abilities.STANCE_SPELL[ns.Abilities.STANCE_ID.berserker])

local function buildMacro(ability, role)
    local lines = { "#showtooltip " .. ability.name }
    if ability.combo then
        table.insert(lines, ("/use [mod:%s] %s"):format(ability.combo.modifier, ability.combo.use))
    end
    -- DPS: hold Ctrl to dance into Berserker first. The player holds it only
    -- when rage is low enough that the switch is free -- the secure button
    -- can't read rage itself, so that judgement stays with them.
    if role == "dps" and isBerserkerSwitchable(ability) then
        table.insert(lines, CTRL_BERSERKER_SWITCH)
    end
    if not ability.stance or ability.stance == "any" then
        table.insert(lines, "/cast " .. ability.name)
    elseif ability.mode == "two_press" then
        table.insert(lines, ("/cast [stance:%s] %s; %s"):format(
            stanceIdList(ability.stance), ability.name, defaultStanceSpell(ability.stance)))
    else
        table.insert(lines, ("/cast [nostance:%s] %s"):format(
            stanceIdList(ability.stance), defaultStanceSpell(ability.stance)))
        table.insert(lines, "/cast " .. ability.name)
    end
    if not ability.noStartAttack then
        table.insert(lines, "/startattack")
    end
    return table.concat(lines, "\n")
end

local function isHidden(ability)
    if not ability then return true end
    if ability.talentOnly and not GetSpellInfo(ability.name) then return true end
    return false
end

-- ---------- per-button UI --------------------------------------------------

local function stanceIconTexture(sid)
    local _, _, icon = GetSpellInfo(ns.Abilities.STANCE_SPELL_ID[sid])
    return icon
end

-- Manual pulse via OnUpdate. Triangle-wave alpha between `from` and `to`,
-- one full bounce per `period` seconds. Replaces AnimationGroup pulsing
-- because the BOUNCE/REPEAT alpha animations weren't actually animating
-- the frame's alpha here.
local function startPulse(frame, from, to, period)
    frame._pulseT = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self._pulseT = (self._pulseT or 0) + elapsed
        local cycle = (self._pulseT / period) % 2
        local progress = cycle <= 1 and cycle or (2 - cycle)
        self:SetAlpha(from + (to - from) * progress)
    end)
end

local function stopPulse(frame)
    frame:SetScript("OnUpdate", nil)
end

-- Four-sided rectangular border ring around a button. Frame alpha controls
-- all four edge textures at once.
local function createBorderGlow(btn, thickness, r, g, b, a, outset)
    outset = outset or 0
    local frame = CreateFrame("Frame", nil, btn)
    frame:SetPoint("CENTER", btn, "CENTER", 0, -1)
    frame:SetSize(BUTTON_SIZE + 2 * outset, BUTTON_SIZE + 2 * outset)
    frame:SetFrameLevel((btn:GetFrameLevel() or 0) + 5)
    frame:Hide()
    local function edge()
        local t = frame:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetVertexColor(r, g, b, a)
        t:SetBlendMode("ADD")
        return t
    end
    local top = edge(); top:SetHeight(thickness)
    top:SetPoint("TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", thickness, thickness)
    local bot = edge(); bot:SetHeight(thickness)
    bot:SetPoint("BOTTOMLEFT", -thickness, -thickness)
    bot:SetPoint("BOTTOMRIGHT", thickness, -thickness)
    local left = edge(); left:SetWidth(thickness)
    left:SetPoint("TOPLEFT", -thickness, 0)
    left:SetPoint("BOTTOMLEFT", -thickness, 0)
    local right = edge(); right:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", thickness, 0)
    right:SetPoint("BOTTOMRIGHT", thickness, 0)
    return frame
end

local function createAbilityButton(parent, name)
    local btn = CreateFrame("Button", "HelloWarrior_" .. name, parent, "SecureActionButtonTemplate")
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:RegisterForClicks("AnyDown", "AnyUp")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Ornate frame border: its own always-on texture so it stays put during a
    -- press (a managed Normal->Pushed frame swap read as too strong).
    local border = btn:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(BUTTON_SIZE * 1.7, BUTTON_SIZE * 1.7)
    border:SetPoint("CENTER", btn, "CENTER", 0, -1)

    -- Subtle click feedback, like the default action bars: a faint darken over
    -- the icon while the button is held (the button's Pushed state). The border
    -- is a separate texture above this, so it stays put. The darken sits over
    -- the 1x icon only, so it never collides with the 1.7x border ring.
    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetColorTexture(0, 0, 0, 0.25)
    pushed:SetAllPoints(icon)
    btn:SetPushedTexture(pushed)

    -- Mouseover highlight over the icon (ADD wash; doesn't hide the art).
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:GetHighlightTexture():SetAllPoints(icon)

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    btn.cooldown = cd

    local stanceCorner = btn:CreateTexture(nil, "OVERLAY")
    stanceCorner:SetSize(12, 12)
    stanceCorner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    stanceCorner:Hide()
    btn.stanceCorner = stanceCorner

    -- Hard flash: fallback ring (only used when Blizzard's overlay isn't available).
    btn.hardFlash = createBorderGlow(btn, 4, 1, 0.95, 0.4, 1.0, 20)
    btn.hardFlash.pulseFrom = 0.55
    btn.hardFlash.pulseTo = 1.0
    btn.hardFlash.pulsePeriod = 0.3
    -- We intentionally do NOT pre-warm or mutate Blizzard's overlay here. Those
    -- frames come from a single GLOBAL pool shared with every action button, so
    -- permanently zeroing a texture on one contaminates whatever button reuses
    -- it later (the old cause of the stuck "yellow square"). Square suppression
    -- is done per-show on the live frame, and restored before the frame is
    -- released, in showHardGlow/hideHardGlow below.

    -- Transient stance-press cue: a thin ring hugging the button edge that
    -- fades once. Signals "stance changed -- your next press casts" without the
    -- big yellow square the old wide gold ring looked like.
    local press = createBorderGlow(btn, 2, 0.5, 0.85, 1.0, 0.9, 2)
    btn.pressFlash = press
    btn.pressFlashStart = nil
    press:SetScript("OnUpdate", function(self, elapsed)
        if not self.pulseStart then return end
        local t = GetTime() - self.pulseStart
        if t >= 0.6 then
            -- Keep the OnUpdate installed (it idles via the pulseStart guard
            -- above). Removing it here meant a button's SECOND stance-press
            -- flash had no handler to fade it, so the ring stuck on screen.
            self.pulseStart = nil
            self:Hide()
            return
        end
        self:SetAlpha(1 - t / 0.6)
    end)

    btn:SetScript("OnEnter", function(self)
        local spell = self.currentAbilityName
        if not spell then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local id = select(7, GetSpellInfo(spell))
        if id then
            GameTooltip:SetSpellByID(id)
        else
            GameTooltip:SetText(spell, 1, 1, 1)
            GameTooltip:AddLine("Not learned yet", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    -- Capture pre-click state for the post-press stance flash.
    btn:HookScript("PreClick", function(self)
        self.lastClickStance = GetShapeshiftForm()
        self.lastClickAt = GetTime()
    end)

    return btn
end

-- ---------- main module ----------------------------------------------------

local function positionKey()
    return HelloWarriorCharDB.hideBlizzardBars and "barPositionBottom" or "barPosition"
end

local function savePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    HelloWarriorCharDB[positionKey()] = { point = point, relPoint = relPoint, x = x, y = y }
end

function AB:UpdatePosition()
    if not self.container then return end
    local pos = HelloWarriorCharDB[positionKey()]
    self.container:ClearAllPoints()
    if pos then
        self.container:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    elseif HelloWarriorCharDB.hideBlizzardBars then
        self.container:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 40)
    else
        self.container:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

local function setSlotMacro(btn, ability, role)
    if not ability or isHidden(ability) then
        return ""
    end
    return buildMacro(ability, role)
end

-- Reversibly toggle Blizzard's default action bars. We use alpha + mouse
-- rather than :Hide so the secure keybindings keep firing and toggling
-- back to visible is straightforward.
local BLIZZ_ART = {
    "MainMenuBarArtFrame",
    "MainMenuBarLeftEndCap",
    "MainMenuBarRightEndCap",
    "ActionBarUpButton",
    "ActionBarDownButton",
    "MainMenuBarPageNumber",
}

local function setBlizzardBarsVisible(visible)
    if InCombatLockdown() then return false end
    for i = 1, 12 do
        for _, prefix in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton" }) do
            local b = _G[prefix .. i]
            if b then
                b:SetAlpha(visible and 1 or 0)
                b:EnableMouse(visible)
            end
        end
    end
    -- Stance bar parents (name varies by patch and UI replacement addon).
    for _, name in ipairs({
        "StanceBarFrame", "StanceBar", "ShapeshiftBarFrame", "PossessBarFrame",
        "DragonflightUIStancebar",
    }) do
        local f = _G[name]
        if f then
            if visible then f:Show() else f:Hide() end
        end
    end
    -- Individual stance buttons (belt & suspenders if a UI re-shows the bar).
    for i = 1, 10 do
        for _, prefix in ipairs({ "StanceButton", "ShapeshiftButton" }) do
            local b = _G[prefix .. i]
            if b then
                b:SetAlpha(visible and 1 or 0)
                b:EnableMouse(visible)
            end
        end
    end
    for _, name in ipairs(BLIZZ_ART) do
        local f = _G[name]
        if f then if visible then f:Show() else f:Hide() end end
    end
    return true
end

local function applyAbilityToButton(btn, ability)
    if not ability or isHidden(ability) then
        btn.currentAbility = nil
        btn.currentAbilityName = nil
        btn.icon:SetTexture(nil)
        btn.stanceCorner:Hide()
        return
    end
    btn.currentAbility = ability
    btn.currentAbilityName = ability.name
    local name, _, icon = GetSpellInfo(ability.name)
    btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- SetTexture resets coords
    btn.icon:SetDesaturated(name == nil)
    local sid = primaryStanceId(ability.stance)
    if sid then
        btn.stanceCorner:SetTexture(stanceIconTexture(sid))
        btn.stanceCorner:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.stanceCorner:Show()
    else
        btn.stanceCorner:Hide()
    end
end

function AB:Build()
    if self.container then return end

    local tankAbils, dpsAbils = ns.Abilities.tank, ns.Abilities.dps
    local shoutAbils = ns.Abilities.shouts
    local maxAbil = math.max(#tankAbils, #dpsAbils)
    local rows = math.ceil(maxAbil / ABILITIES_PER_ROW)
    local rowWidth = ABILITIES_PER_ROW * BUTTON_SIZE + (ABILITIES_PER_ROW - 1) * BUTTON_GAP
    local abilitiesHeight = rows * BUTTON_SIZE + (rows - 1) * ROW_GAP
    -- +1 column for the prepended ranged-attack button.
    local shoutsWidth = (#shoutAbils + 1) * BUTTON_SIZE + #shoutAbils * BUTTON_GAP
    local headerHeight = 24
    local totalHeight = headerHeight + SECTION_GAP + abilitiesHeight + SECTION_GAP + BUTTON_SIZE

    -- Container (drag handle for the whole cluster).
    local container = CreateFrame("Frame", "HelloWarrior_Container", UIParent)
    container:SetSize(rowWidth, totalHeight)
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self) self:StartMoving() end)
    container:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    self.container = container
    self:UpdatePosition()
    if HelloWarriorCharDB.showHWBars == false then container:Hide() end

    -- Abilities bar (secure handler for role swap).
    local bar = CreateFrame("Frame", "HelloWarrior_AbilityBar", container, "SecureHandlerStateTemplate")
    bar:SetSize(rowWidth, abilitiesHeight)
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(headerHeight + SECTION_GAP + BUTTON_SIZE + SECTION_GAP))
    self.bar = bar

    -- Create one button per slot up to maxAbil.
    self.buttons = {}
    for i = 1, maxAbil do
        local nameSuffix = string.format("Slot%02d", i)
        local btn = createAbilityButton(bar, nameSuffix)
        local row = math.floor((i - 1) / ABILITIES_PER_ROW)
        local col = (i - 1) % ABILITIES_PER_ROW
        btn:SetPoint("TOPLEFT", bar, "TOPLEFT",
            col * (BUTTON_SIZE + BUTTON_GAP),
            -row * (BUTTON_SIZE + ROW_GAP))

        local tankAb = tankAbils[i]
        local dpsAb  = dpsAbils[i]
        btn.tankAbility = tankAb
        btn.dpsAbility  = dpsAb
        btn:SetAttribute("macrotext-tank", setSlotMacro(btn, tankAb, "tank"))
        btn:SetAttribute("macrotext-dps",  setSlotMacro(btn, dpsAb, "dps"))
        btn:SetAttribute("type", "macro")

        bar:SetFrameRef("btn" .. i, btn)
        self.buttons[i] = btn
    end
    bar:SetAttribute("btnCount", maxAbil)

    bar:SetAttribute("baseRole", HelloWarriorCharDB.role or "dps")
    bar:SetAttribute("modActive", "0")

    bar:SetAttribute("UpdateRole", [[
        local base = self:GetAttribute("baseRole") or "dps"
        local mod = self:GetAttribute("modActive") == "1"
        local effective = base
        if mod then effective = (base == "tank") and "dps" or "tank" end
        self:SetAttribute("effectiveRole", effective)
        local count = self:GetAttribute("btnCount") or 0
        for i = 1, count do
            local b = self:GetFrameRef("btn" .. i)
            if b then
                local mt = b:GetAttribute("macrotext-" .. effective)
                if mt and mt ~= "" then
                    b:Show()
                    b:SetAttribute("macrotext", mt)
                else
                    b:Hide()
                end
            end
        end
    ]])

    bar:SetAttribute("_onstate-mod", [[
        self:SetAttribute("modActive", (newstate == "on") and "1" or "0")
        self:RunAttribute("UpdateRole")
    ]])
    bar:HookScript("OnAttributeChanged", function(self, name, value)
        if name and name:lower() == "effectiverole" then
            AB:OnRoleApplied(value)
        end
    end)
    RegisterStateDriver(bar, "mod", "[mod:alt] on; off")

    -- Shouts bar (no role swap; all share both roles). The ranged-attack
    -- button is prepended as the leftmost slot -- it's role-agnostic too.
    local shouts = CreateFrame("Frame", "HelloWarrior_ShoutsBar", container)
    shouts:SetSize(shoutsWidth, BUTTON_SIZE)
    shouts:SetPoint("TOP", container, "TOP", 0, -(headerHeight + SECTION_GAP))
    self.shoutsBar = shouts

    -- Ranged attack: one button that fires whatever ranged weapon is equipped.
    -- The macro is static (worn-conditionals pick the ability), so it never
    -- needs a combat-time update; only the icon/tooltip track the weapon.
    local ranged = createAbilityButton(shouts, "Ranged")
    ranged:RegisterForClicks("AnyUp")  -- single fire (Throw must not double-cast)
    ranged:SetPoint("LEFT", shouts, "LEFT", 0, 0)
    ranged:SetAttribute("type", "macro")
    ranged:SetAttribute("macrotext", RANGED_MACRO)
    ranged.stanceCorner:Hide()
    ranged:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.hasRanged then
            GameTooltip:SetInventoryItem("player", RANGED_SLOT)
        else
            GameTooltip:SetText("Ranged Attack", 1, 1, 1)
            GameTooltip:AddLine("Equip a gun, bow, crossbow, or thrown weapon.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    self.rangedButton = ranged
    self:UpdateRanged()

    self.shoutButtons = {}
    for i, ab in ipairs(shoutAbils) do
        local btn = createAbilityButton(shouts, "Shout" .. i)
        if i == 1 then
            btn:SetPoint("LEFT", ranged, "RIGHT", BUTTON_GAP, 0)
        else
            btn:SetPoint("LEFT", self.shoutButtons[i - 1], "RIGHT", BUTTON_GAP, 0)
        end
        btn:SetAttribute("type", "macro")
        if isHidden(ab) then
            btn:Hide()
        else
            btn:SetAttribute("macrotext", buildMacro(ab))
            applyAbilityToButton(btn, ab)
        end
        self.shoutButtons[i] = btn
    end

    -- Header row: stance indicator + role toggle.
    ns.StanceIndicator:Build(container)
    ns.StanceIndicator.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    ns.RoleToggle:Build(container, bar)
    ns.RoleToggle.frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -1)

    -- Push the initial role through the snippet (out of combat).
    bar:Execute([[ self:RunAttribute("UpdateRole") ]])
    AB:OnRoleApplied(bar:GetAttribute("effectiveRole") or HelloWarriorCharDB.role or "dps")

    self:ApplyBlizzardBars()
    -- Re-apply after a beat to catch UI replacement addons that set up
    -- their bars later in the load cycle.
    C_Timer.After(0.5, function() if AB.container then AB:ApplyBlizzardBars() end end)
    C_Timer.After(2.0, function() if AB.container then AB:ApplyBlizzardBars() end end)

    -- Periodic tick for flash/rage/cooldown.
    self.ticker = C_Timer.NewTicker(0.1, function() AB:Tick() end)
end

-- Track the equipped ranged weapon: icon + tooltip follow it, and the button
-- desaturates to a generic glyph when nothing ranged is equipped. Purely
-- cosmetic (no Show/Hide), so it's safe to run in combat; the macro itself is
-- static and fires the right ability via its worn-conditionals.
function AB:UpdateRanged()
    local btn = self.rangedButton
    if not btn then return end
    local tex = GetInventoryItemTexture("player", RANGED_SLOT)
    btn.hasRanged = tex ~= nil
    btn.icon:SetTexture(tex or RANGED_EMPTY_ICON)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- SetTexture resets coords
    btn.icon:SetDesaturated(not btn.hasRanged)
end

function AB:ApplyBlizzardBars()
    setBlizzardBarsVisible(not HelloWarriorCharDB.hideBlizzardBars)
end

function AB:SetBlizzardBarsHidden(hide)
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't toggle bars in combat.")
        return
    end
    HelloWarriorCharDB.hideBlizzardBars = hide and true or false
    self:ApplyBlizzardBars()
    self:UpdatePosition()
end

function AB:SetHWBarsVisible(visible)
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't toggle bars in combat.")
        return
    end
    HelloWarriorCharDB.showHWBars = visible and true or false
    if not self.container then return end
    if visible then self.container:Show() else self.container:Hide() end
end

function AB:CurrentAbility(slotBtn)
    local role = self.bar and self.bar:GetAttribute("effectiveRole") or HelloWarriorCharDB.role or "dps"
    return (role == "tank") and slotBtn.tankAbility or slotBtn.dpsAbility
end

function AB:OnRoleApplied(role)
    if not self.buttons then return end
    for _, btn in ipairs(self.buttons) do
        local ab = (role == "tank") and btn.tankAbility or btn.dpsAbility
        applyAbilityToButton(btn, ab)
    end
    self:Tick()
end

local function updateCooldown(btn, spellName)
    local start, duration = GetSpellCooldown(spellName)
    if start and duration and duration > 1.5 then
        btn.cooldown:SetCooldown(start, duration)
    else
        btn.cooldown:Clear()
    end
end

local function updateRageTint(btn, spellName)
    local usable, noPower = IsUsableSpell(spellName)
    if not usable and noPower then
        btn.icon:SetVertexColor(0.6, 0.6, 0.9)
    elseif not usable then
        btn.icon:SetVertexColor(0.4, 0.4, 0.4)
    else
        btn.icon:SetVertexColor(1, 1, 1)
    end
end

local function updateStanceCorner(btn)
    if not btn.currentAbility then return end
    local ab = btn.currentAbility
    if not ab.stance or ab.stance == "any" then
        btn.stanceCorner:Hide()
        return
    end
    btn.stanceCorner:Show()
    if stanceMatches(ab.stance) then
        btn.stanceCorner:SetAlpha(0.35)  -- dim when satisfied
    else
        btn.stanceCorner:SetAlpha(1.0)   -- glow when needed
    end
end

local function showRing(frame)
    if frame:IsShown() then return end
    frame:Show()
    startPulse(frame, frame.pulseFrom, frame.pulseTo, frame.pulsePeriod)
end

local function hideRing(frame)
    if not frame:IsShown() then return end
    stopPulse(frame)
    frame:Hide()
end

-- Blizzard's spell-activation overlay is a static "alert" square (texture
-- Interface\SpellActivationOverlay\IconAlert: spark + inner/outer glow) plus the
-- marching-ants spin (IconAlertAnts). We want the spin, not the square: on each
-- show we zero the square textures' vertex alpha on the *live* overlay frame,
-- and restore them before the frame goes back to the pool. The ants texture is
-- explicitly excluded so the spinning animation is never touched.
local SQUARE_KEY = "_hwSavedVertex"

local function forEachSquareRegion(overlay, fn)
    if not overlay or not overlay.GetRegions then return end
    for _, region in ipairs({ overlay:GetRegions() }) do
        if region.GetTexture then
            local tex = region:GetTexture()
            if type(tex) == "string" then
                local lower = tex:lower()
                if lower:find("spellactivationoverlay", 1, true)
                   and not lower:find("ants", 1, true) then
                    fn(region)
                end
            end
        end
    end
end

local function suppressOverlaySquare(overlay)
    forEachSquareRegion(overlay, function(region)
        -- Save-once, and never snapshot an already-suppressed (alpha 0) value,
        -- so a missed restore can't make the contamination self-perpetuating.
        if not region[SQUARE_KEY] then
            local r, g, b, a = region:GetVertexColor()
            region[SQUARE_KEY] = { r or 1, g or 1, b or 1, a or 1 }
        end
        region:SetVertexColor(1, 1, 1, 0)
    end)
end

local function restoreOverlaySquare(overlay)
    forEachSquareRegion(overlay, function(region)
        local saved = region[SQUARE_KEY]
        if saved then
            region:SetVertexColor(saved[1], saved[2], saved[3], saved[4])
            region[SQUARE_KEY] = nil
        end
    end)
end

-- Restore our square suppression and return the Blizzard overlay frame to the
-- pool, clearing btn.overlay. Safe to call whenever btn.overlay is set,
-- regardless of hardGlowOn, so a frame can never be stranded (e.g. if a show
-- assigned btn.overlay and then errored). Restore runs on a local ref BEFORE
-- the frame can be pooled, because OverlayGlowAnimOutFinished hides + pools +
-- nils btn.overlay synchronously (notably on a hidden button).
local function releaseOverlay(btn)
    local overlay = btn.overlay
    if not overlay then return end
    pcall(restoreOverlaySquare, overlay)
    if overlay.animIn and overlay.animIn:IsPlaying() then overlay.animIn:Stop() end
    if overlay.animOut and overlay.animOut:IsPlaying() then overlay.animOut:Stop() end
    -- OverlayGlowAnimOutFinished is the only path that hides the frame, returns
    -- it to the pool and clears btn.overlay, so the next show acquires a clean
    -- frame and animates fresh. (The fade-out is skipped; the glow snaps off,
    -- which is deterministic under the 0.1s ticker.)
    if ActionButton_OverlayGlowAnimOutFinished and overlay.animOut then
        pcall(ActionButton_OverlayGlowAnimOutFinished, overlay.animOut)
    else
        -- Not expected on Classic Era 1.15.x (the finisher ships alongside
        -- Show/Hide). Blizzard's pool is private, so just drop our ref and let
        -- the next show acquire a fresh frame.
        overlay:Hide()
        btn.overlay = nil
    end
end

-- ActionButton_ShowOverlayGlow reparents a pooled frame onto our button from an
-- insecure path (the ticker / shapeshift handler). This is the same call every
-- default action button makes, and it never touches our secure cast attributes
-- (type/macrotext), so click-to-cast stays secure; accepted tradeoff for using
-- Blizzard's native animated glow.
local function showHardGlow(btn)
    -- Reconcile stale intent: if Blizzard reclaimed the pooled frame out from
    -- under us, btn.overlay is nil while hardGlowOn still says "overlay". Clear
    -- it so the guard below can't permanently block re-showing the glow.
    if btn.hardGlowOn == "overlay" and not btn.overlay then
        btn.hardGlowOn = nil
    end
    if btn.hardGlowOn then return end
    if ActionButton_ShowOverlayGlow then
        local ok = pcall(ActionButton_ShowOverlayGlow, btn)
        if ok and btn.overlay then
            suppressOverlaySquare(btn.overlay)
            btn.hardGlowOn = "overlay"
            return
        end
        -- ShowOverlayGlow can assign btn.overlay and THEN error; release that
        -- partial frame so it can't dangle (unsuppressed) behind the ring.
        releaseOverlay(btn)
    end
    showRing(btn.hardFlash)
    btn.hardGlowOn = "fallback"
end

local function hideHardGlow(btn)
    if not btn.hardGlowOn and not btn.overlay then return end
    -- Tear the fallback ring down if it's up...
    if btn.hardGlowOn == "fallback" then
        hideRing(btn.hardFlash)
    end
    -- ...and ALWAYS release any overlay frame we hold, even in fallback mode: a
    -- failed show can leave btn.overlay set while hardGlowOn=="fallback", and
    -- that frame must never be left shown/un-pooled.
    releaseOverlay(btn)
    btn.hardGlowOn = nil
end

local function applyFlash(btn, flash)
    -- Only glow buttons that are actually on screen. Secure role/stance swaps
    -- :Hide() buttons without routing through here; gating on IsVisible means
    -- the next tick tears the glow down (restoring + pooling the frame) for any
    -- button that became hidden, rather than stranding a suppressed frame.
    if flash.hard and btn:IsVisible() then
        showHardGlow(btn)
    else
        hideHardGlow(btn)
    end
end

function AB:Tick()
    if not self.buttons then return end
    local role = self.bar and self.bar:GetAttribute("effectiveRole") or HelloWarriorCharDB.role or "dps"
    local flashResults = ns.Helper:Compute(role)

    for _, btn in ipairs(self.buttons) do
        local ab = btn.currentAbility
        if ab and GetSpellInfo(ab.name) then
            updateCooldown(btn, ab.name)
            updateRageTint(btn, ab.name)
            updateStanceCorner(btn)
            applyFlash(btn, flashResults[ab.name] or {})
        else
            btn.cooldown:Clear()
            applyFlash(btn, {})
        end
    end

    -- Shouts: cooldown + rage tint + optional maintenance flash (e.g. Battle Shout).
    for _, btn in ipairs(self.shoutButtons or {}) do
        local ab = btn.currentAbility
        if ab and GetSpellInfo(ab.name) then
            updateCooldown(btn, ab.name)
            updateRageTint(btn, ab.name)
            applyFlash(btn, flashResults[ab.name] or {})
        else
            applyFlash(btn, {})
        end
    end
end

-- Detect post-press stance flash: after a button press, if the stance changed
-- to match the ability's required stance, fire the transient flash so the user
-- knows their next press will be the actual cast.
local function maybePressFlash()
    if not AB.buttons then return end
    local now = GetTime()
    local newStance = GetShapeshiftForm()
    for _, btn in ipairs(AB.buttons) do
        if btn.lastClickAt and (now - btn.lastClickAt) < 0.5 then
            local ab = btn.currentAbility
            if ab and ab.stance and ab.stance ~= "any" then
                local matches = stanceMatches(ab.stance)
                local wasInWrongStance = (btn.lastClickStance or 0) ~= newStance
                if matches and wasInWrongStance then
                    if not btn.pressFlash.pulseStart then
                        btn.pressFlash:SetAlpha(1)
                        btn.pressFlash:Show()
                        btn.pressFlash.pulseStart = GetTime()
                    end
                end
            end
            btn.lastClickAt = nil
        end
    end
end

function AB:RefreshLayout()
    -- Re-evaluate macrotexts (talent learns / respec).
    if not self.buttons then return end
    if InCombatLockdown() then return end
    for i, btn in ipairs(self.buttons) do
        btn:SetAttribute("macrotext-tank", setSlotMacro(btn, btn.tankAbility, "tank"))
        btn:SetAttribute("macrotext-dps",  setSlotMacro(btn, btn.dpsAbility, "dps"))
    end
    for _, btn in ipairs(self.shoutButtons or {}) do
        if btn.currentAbility then
            if isHidden(btn.currentAbility) then
                btn:Hide()
            else
                btn:Show()
                btn:SetAttribute("macrotext", buildMacro(btn.currentAbility))
            end
        end
    end
    self.bar:Execute([[ self:RunAttribute("UpdateRole") ]])
end

ns:On("PLAYER_LOGIN", function()
    if not ns.enabled then return end
    AB:Build()
end)
ns:On("SPELLS_CHANGED",      function() AB:RefreshLayout() end)
ns:On("PLAYER_REGEN_ENABLED", function() AB:RefreshLayout(); AB:ApplyBlizzardBars() end)
ns:On("PLAYER_ENTERING_WORLD",       function() AB:ApplyBlizzardBars(); AB:UpdateRanged() end)
ns:On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then AB:UpdateRanged() end
end)
ns:On("UPDATE_SHAPESHIFT_FORM", function()
    maybePressFlash()
    AB:Tick()
end)
ns:On("UNIT_POWER_UPDATE", function(unit)
    if unit == "player" then AB:Tick() end
end)
ns:On("PLAYER_TARGET_CHANGED", function() AB:Tick() end)
