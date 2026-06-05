local ADDON_NAME, ns = ...

ns.ActionBar = {}
local AB = ns.ActionBar

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local ABILITIES_PER_ROW = 8
local ROW_GAP = 4
local SECTION_GAP = 10
local RAGE_POWER_TYPE = Enum and Enum.PowerType and Enum.PowerType.Rage or 1

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

local function buildMacro(ability)
    local lines = { "#showtooltip " .. ability.name }
    if ability.combo then
        table.insert(lines, ("/use [mod:%s] %s"):format(ability.combo.modifier, ability.combo.use))
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
    table.insert(lines, "/startattack")
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

-- Four-sided border ring around a button. Returns a Frame whose alpha controls
-- all four edge textures together, so animating the frame's alpha pulses the
-- whole ring without painting over the icon underneath.
local function createBorderGlow(btn, thickness, r, g, b, a)
    local frame = CreateFrame("Frame", nil, btn)
    frame:SetAllPoints(btn)
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

    local border = btn:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(BUTTON_SIZE * 1.5, BUTTON_SIZE * 1.5)
    border:SetPoint("CENTER", btn, "CENTER", 0, -1)

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    btn.cooldown = cd

    local stanceCorner = btn:CreateTexture(nil, "OVERLAY")
    stanceCorner:SetSize(12, 12)
    stanceCorner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    stanceCorner:Hide()
    btn.stanceCorner = stanceCorner

    -- Soft flash: thin yellow ring, slow pulse.
    local soft = createBorderGlow(btn, 2, 1, 0.9, 0.25, 0.7)
    local softAg = soft:CreateAnimationGroup()
    softAg:SetLooping("BOUNCE")
    local softA = softAg:CreateAnimation("Alpha")
    softA:SetFromAlpha(0.35); softA:SetToAlpha(1.0); softA:SetDuration(0.6)
    btn.softFlash = soft
    btn.softFlashAg = softAg

    -- Hard flash: thicker, brighter, faster pulse.
    local hard = createBorderGlow(btn, 3, 1, 0.95, 0.4, 1.0)
    local hardAg = hard:CreateAnimationGroup()
    hardAg:SetLooping("BOUNCE")
    local hardA = hardAg:CreateAnimation("Alpha")
    hardA:SetFromAlpha(0.55); hardA:SetToAlpha(1.0); hardA:SetDuration(0.3)
    btn.hardFlash = hard
    btn.hardFlashAg = hardAg

    -- Transient stance-press flash: gold ring fades out once.
    local press = createBorderGlow(btn, 4, 1, 0.85, 0.1, 1.0)
    local pressAg = press:CreateAnimationGroup()
    local pressA = pressAg:CreateAnimation("Alpha")
    pressA:SetFromAlpha(1.0); pressA:SetToAlpha(0); pressA:SetDuration(1.4)
    pressAg:SetScript("OnFinished", function() press:Hide() end)
    btn.pressFlash = press
    btn.pressFlashAg = pressAg

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

local function setSlotMacro(btn, ability)
    if not ability or isHidden(ability) then
        return ""
    end
    return buildMacro(ability)
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
    local shoutsWidth = #shoutAbils * BUTTON_SIZE + (#shoutAbils - 1) * BUTTON_GAP
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
    bar:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(headerHeight + SECTION_GAP))
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
        btn:SetAttribute("macrotext-tank", setSlotMacro(btn, tankAb))
        btn:SetAttribute("macrotext-dps",  setSlotMacro(btn, dpsAb))
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

    -- Shouts bar (no role swap; all 5 share both roles).
    local shouts = CreateFrame("Frame", "HelloWarrior_ShoutsBar", container)
    shouts:SetSize(shoutsWidth, BUTTON_SIZE)
    shouts:SetPoint("TOP", bar, "BOTTOM", 0, -SECTION_GAP)
    self.shoutsBar = shouts
    self.shoutButtons = {}
    for i, ab in ipairs(shoutAbils) do
        local btn = createAbilityButton(shouts, "Shout" .. i)
        if i == 1 then
            btn:SetPoint("LEFT", shouts, "LEFT", 0, 0)
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

local function showHardGlow(btn)
    if btn.hardGlowOn then return end
    if ActionButton_ShowOverlayGlow then
        local ok = pcall(ActionButton_ShowOverlayGlow, btn)
        if ok then btn.hardGlowOn = "overlay"; return end
    end
    if not btn.hardFlashAg:IsPlaying() then
        btn.hardFlash:Show(); btn.hardFlashAg:Play()
    end
    btn.hardGlowOn = "fallback"
end

local function hideHardGlow(btn)
    if not btn.hardGlowOn then return end
    if btn.hardGlowOn == "overlay" and ActionButton_HideOverlayGlow then
        pcall(ActionButton_HideOverlayGlow, btn)
    else
        btn.hardFlash:Hide(); btn.hardFlashAg:Stop()
    end
    btn.hardGlowOn = nil
end

local function applyFlash(btn, flash)
    if flash.hard then
        btn.softFlash:Hide(); btn.softFlashAg:Stop()
        showHardGlow(btn)
    elseif flash.soft then
        hideHardGlow(btn)
        if not btn.softFlashAg:IsPlaying() then
            btn.softFlash:Show(); btn.softFlashAg:Play()
        end
    else
        hideHardGlow(btn)
        btn.softFlash:Hide(); btn.softFlashAg:Stop()
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

    -- Shouts: cooldown + rage tint only, no flash.
    for _, btn in ipairs(self.shoutButtons or {}) do
        local ab = btn.currentAbility
        if ab and GetSpellInfo(ab.name) then
            updateCooldown(btn, ab.name)
            updateRageTint(btn, ab.name)
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
                    if not btn.pressFlashAg:IsPlaying() then
                        btn.pressFlash:Show()
                        btn.pressFlashAg:Play()
                    end
                end
            end
            btn.lastClickAt = nil
        end
    end
end

function AB:SetRole(role)
    if role ~= "tank" and role ~= "dps" then return end
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't change role in combat — use the toggle or Alt overlay.")
        return
    end
    if not self.bar then return end
    HelloWarriorCharDB.role = role
    self.bar:SetAttribute("baseRole", role)
    self.bar:Execute([[ self:RunAttribute("UpdateRole") ]])
    ns.RoleToggle:Refresh()
    print("|cffc79c6eHelloWarrior|r role: " .. role)
end

function AB:ToggleRole()
    local cur = HelloWarriorCharDB.role or "dps"
    self:SetRole(cur == "tank" and "dps" or "tank")
end

-- Pick a role from the talent tree breakdown. Prot leading (and non-zero) =
-- tank; anything else = dps. Tabs: 1 = Arms, 2 = Fury, 3 = Protection.
-- With dual spec, GetTalentTabInfo without a group argument can race the
-- swap, so explicitly pass the active talent group.
local function detectRoleFromTalents()
    if not GetTalentTabInfo then return nil end
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or nil
    local function pointsIn(tab)
        local _, _, p = GetTalentTabInfo(tab, false, false, group)
        return p or 0
    end
    local arms, fury, prot = pointsIn(1), pointsIn(2), pointsIn(3)
    if prot > 0 and prot >= arms and prot >= fury then return "tank" end
    return "dps"
end

function AB:DetectAndApplyRole()
    if not GetTalentTabInfo then return end
    local group = GetActiveTalentGroup and GetActiveTalentGroup() or nil
    local function pointsIn(tab)
        local _, _, _, _, pts = GetTalentTabInfo(tab, false, false, group)
        return tonumber(pts) or 0
    end
    local _, _, prot = pointsIn(1), pointsIn(2), pointsIn(3)
    local detected = (prot > 0) and "tank" or "dps"
    if detected == HelloWarriorCharDB.role then return end
    self:SetRole(detected)
end

function AB:RefreshLayout()
    -- Re-evaluate macrotexts (talent learns / respec).
    if not self.buttons then return end
    if InCombatLockdown() then return end
    for i, btn in ipairs(self.buttons) do
        btn:SetAttribute("macrotext-tank", setSlotMacro(btn, btn.tankAbility))
        btn:SetAttribute("macrotext-dps",  setSlotMacro(btn, btn.dpsAbility))
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
local function scheduleDetect()
    C_Timer.After(0.4, function() AB:DetectAndApplyRole() end)
end
ns:On("PLAYER_TALENT_UPDATE",        scheduleDetect)
ns:On("CHARACTER_POINTS_CHANGED",    scheduleDetect)
ns:On("ACTIVE_TALENT_GROUP_CHANGED", scheduleDetect)
ns:On("PLAYER_ENTERING_WORLD",       function() AB:ApplyBlizzardBars() end)
ns:On("UPDATE_SHAPESHIFT_FORM", function()
    maybePressFlash()
    AB:Tick()
end)
ns:On("UNIT_POWER_UPDATE", function(unit)
    if unit == "player" then AB:Tick() end
end)
ns:On("PLAYER_TARGET_CHANGED", function() AB:Tick() end)
