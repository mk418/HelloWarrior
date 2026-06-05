local ADDON_NAME, ns = ...

ns.ActionBar = {}
local AB = ns.ActionBar

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local ABILITIES_PER_ROW = 7
local ROW_GAP = 4
local SECTION_GAP = 10
local RAGE_POWER_TYPE = Enum and Enum.PowerType and Enum.PowerType.Rage or 1
local HEADER_BAR_HEIGHT = 12  -- rage + swing timer stack in the header band

-- Rage-cap warning. While ns.Helper:IsRageCapping() is true (>=80% rage in
-- combat -- the single shared trigger that also lights up Heroic Strike / Cleave
-- in Helper:Compute), the rage bar throbs from its base red toward a hot warning
-- colour so you dump the excess instead of wasting it.
local RAGE_BASE_COLOR = { 0.78, 0.25, 0.25 }  -- rage red (the bar's resting colour)
local RAGE_WARN_COLOR = { 1.0, 0.55, 0.10 }   -- hot orange it pulses toward
local RAGE_WARN_PERIOD = 0.5                   -- seconds per half-cycle (full throb = 1s)

-- Ranged-attack button. One macro fires whichever ranged weapon is equipped
-- via [worn:...] conditionals, so only the matching ability is cast. "!" keeps
-- the auto-repeat Shoot abilities firing instead of toggling off; Throw is a
-- single cast so it gets no "!". Works in every stance; no /startattack (that
-- starts melee auto-attack, the opposite of a ranged pull).
local RANGED_SLOT = 18  -- INVSLOT_RANGED
local RANGED_MACRO = "/cast [worn:Guns] !Shoot Gun; [worn:Bows] !Shoot Bow; [worn:Crossbows] !Shoot Crossbow; [worn:Thrown] Throw"
local RANGED_EMPTY_ICON = "Interface\\Icons\\Ability_Marksmanship"

-- Off-hand swap toggle. INVSLOT_OFFHAND is 17; the glyph falls back to this
-- generic icon until both ends of the toggle are saved (see AB:SaveOffhandSwap).
local OFFHAND_SLOT = 17  -- INVSLOT_OFFHAND
local SWAP_EMPTY_ICON = "Interface\\Icons\\Ability_Warrior_ShieldWall"

-- True while `name`'s ability is queued for the next melee swing. Resolve the
-- player's LEARNED-rank spellID straight from the name via GetSpellInfo's 7th
-- return -- the same call the rest of the addon uses -- then ask IsCurrentSpell.
-- (Resolving by name, not a hardcoded base ID, matters because IsCurrentSpell is
-- rank-specific and the learned rank is what /cast queues; an earlier version
-- used GetSpellName(baseID), but that global takes a spellbook index on Classic
-- Era, not a spell ID, so it silently returned the wrong thing.) Heroic Strike
-- and Cleave are instant, so a "current" spell can only mean "queued on next
-- swing" -- there's no cast bar to confuse it with.
-- Resolve once: the global on Classic Era, C_Spell on newer-API clients. If
-- neither exists the feature self-disables (isQueued returns false) instead of
-- erroring every tick.
local isCurrentSpell = IsCurrentSpell or (C_Spell and C_Spell.IsCurrentSpell)

local function isQueued(name)
    if not isCurrentSpell then return false end
    local rankID = name and select(7, GetSpellInfo(name))
    return rankID and isCurrentSpell(rankID) or false
end

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

-- True when a preferred-stance switch should be PREPENDED so `ability` dances
-- into `stanceName`: "any"-stance abilities (the macro otherwise adds no switch)
-- and multi-stance abilities that include stanceName alongside another stance
-- (so we can prefer it even from the other valid stance). Single-stance
-- abilities already dance into their own stance; abilities that can't be used in
-- stanceName at all are left alone, so we never pull them out of a needed stance.
local function canSwitchTo(ability, stanceName)
    local s = ability.stance
    if s == nil or s == "any" then return true end
    if type(s) == "table" then
        local hasIt, hasOther = false, false
        for _, v in ipairs(s) do
            if v == stanceName then hasIt = true else hasOther = true end
        end
        return hasIt and hasOther
    end
    return false
end

local CTRL_BERSERKER_SWITCH = ("/cast [mod:ctrl,nostance:%d] %s"):format(
    ns.Abilities.STANCE_ID.berserker,
    ns.Abilities.STANCE_SPELL[ns.Abilities.STANCE_ID.berserker])

local DEFENSIVE_SWITCH = ("/cast [nostance:%d] %s"):format(
    ns.Abilities.STANCE_ID.defensive,
    ns.Abilities.STANCE_SPELL[ns.Abilities.STANCE_ID.defensive])

-- Pre-built /cancelaura blocks per role, folded into every ability macro so
-- using an ability strips unwanted buffs. /cancelaura works in AND out of
-- combat on Classic Era, and canceling a buff you don't have is a silent no-op,
-- so these lines fire whenever you press (no [nocombat] guard). Tank also drops
-- the Salvation threat-reducers.
local CANCEL_BY_ROLE = {}
do
    local function block(role)
        local lines = {}
        -- Role-specific buffs FIRST (tank Salvation): they're the ones that
        -- actually matter, so if a macro-length cap ever truncates the tail it
        -- drops a cosmetic caster line, not the threat-reducing Salvation.
        if role == "tank" then
            for _, name in ipairs(ns.Abilities.unwantedBuffs.tank) do
                lines[#lines + 1] = "/cancelaura " .. name
            end
        end
        for _, name in ipairs(ns.Abilities.unwantedBuffs.both) do
            lines[#lines + 1] = "/cancelaura " .. name
        end
        return lines
    end
    CANCEL_BY_ROLE.tank = block("tank")
    CANCEL_BY_ROLE.dps = block("dps")
end

local function buildMacro(ability, role)
    local lines = { "#showtooltip " .. ability.name }
    if ability.combo then
        table.insert(lines, ("/use [mod:%s] %s"):format(ability.combo.modifier, ability.combo.use))
    end
    -- Prefer your role's home stance for abilities that can use it. DPS: hold
    -- Ctrl to dance into Berserker (opt-in, since the switch can dump rage and a
    -- secure button can't read rage to decide). Tank: always dance into
    -- Defensive -- tanks want to be there, and the switch only fires when you're
    -- not already in Defensive (i.e. returning from a Battle/Berserker dip).
    if role == "dps" and canSwitchTo(ability, "berserker") then
        table.insert(lines, CTRL_BERSERKER_SWITCH)
    elseif role == "tank" and canSwitchTo(ability, "defensive") then
        table.insert(lines, DEFENSIVE_SWITCH)
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
    -- Strip unwanted buffs as a side-effect of the press (in or out of combat).
    -- Role-aware; shouts and the ranged button pass no role and are untouched.
    local cancels = role and CANCEL_BY_ROLE[role]
    if cancels then
        for _, line in ipairs(cancels) do
            table.insert(lines, line)
        end
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
    -- ONE click edge only. A secure macro button runs its full macrotext once
    -- per registered edge, so "AnyDown","AnyUp" fired every press twice: the
    -- down-click cast the ability (starting the GCD) and the up-click re-cast it
    -- mid-GCD, which is what triggered the constant "That ability isn't ready
    -- yet." Casting on up matches Blizzard's default bars and the ranged button.
    btn:RegisterForClicks("AnyUp")

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
    -- Last (start, duration) pushed to the cooldown frame; 0,0 == cleared. The
    -- Tick guard compares against these to skip redundant SetCooldown churn.
    btn._cdStart, btn._cdDuration = 0, 0

    local stanceCorner = btn:CreateTexture(nil, "OVERLAY")
    stanceCorner:SetSize(12, 12)
    stanceCorner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
    stanceCorner:Hide()
    btn.stanceCorner = stanceCorner

    -- "Queued on next swing" cue (Heroic Strike / Cleave waiting for the next
    -- melee swing): the shared pet-autocast spinning shine, toggled in AB:Tick.
    -- The marching sparkle shimmer reads distinctly from the gold optimal ring
    -- (solid pulsing edge) and the cyan stance-press ring (single fading edge).
    ns:AttachShine(btn, BUTTON_SIZE)

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

local function savePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    HelloWarriorCharDB.barPosition = { point = point, relPoint = relPoint, x = x, y = y }
end

function AB:UpdatePosition()
    if not self.container then return end
    local pos = HelloWarriorCharDB.barPosition
    self.container:ClearAllPoints()
    if pos then
        self.container:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        self.container:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    end
end

-- Lock/unlock dragging the whole cluster. Locked == mouse disabled on the
-- container (the drag handle), so clicks pass through and it can't be moved; the
-- move-mode backdrop shows only while unlocked so the transparent cluster is
-- visible and grabbable. EnableMouse + texture toggles aren't combat-protected.
function AB:SetLocked(locked)
    HelloWarriorCharDB.locked = locked and true or false
    if not self.container then return end
    self.container:EnableMouse(not HelloWarriorCharDB.locked)
    if self.moveBg then
        if HelloWarriorCharDB.locked then self.moveBg:Hide() else self.moveBg:Show() end
    end
end

-- Drop the saved position so UpdatePosition falls back to the default spot.
function AB:ResetPosition()
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't move the bars in combat.")
        return
    end
    HelloWarriorCharDB.barPosition = nil
    self:UpdatePosition()
end

local function setSlotMacro(btn, ability, role)
    if not ability or isHidden(ability) then
        return ""
    end
    return buildMacro(ability, role)
end

local function applyAbilityToButton(btn, ability)
    if not ability or isHidden(ability) then
        btn.currentAbility = nil
        btn.currentAbilityName = nil
        btn.icon:SetTexture(nil)
        btn.stanceCorner:Hide()
        ns:SetShine(btn, false)
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
    -- The bottom row also carries the player's own active race racials (only
    -- your race contributes; you can't cast another's). Filter to spells you
    -- actually have so a typo'd/unknown entry simply doesn't appear. raceToken
    -- is UnitRace's 2nd, locale-independent return.
    local _, raceToken = UnitRace("player")
    local racialAbils = {}
    for _, ab in ipairs((ns.Abilities.racials and ns.Abilities.racials[raceToken]) or {}) do
        if GetSpellInfo(ab.name) then racialAbils[#racialAbils + 1] = ab end
    end
    local maxAbil = math.max(#tankAbils, #dpsAbils)
    local rows = math.ceil(maxAbil / ABILITIES_PER_ROW)
    local rowWidth = ABILITIES_PER_ROW * BUTTON_SIZE + (ABILITIES_PER_ROW - 1) * BUTTON_GAP
    local abilitiesHeight = rows * BUTTON_SIZE + (rows - 1) * ROW_GAP
    -- Bottom row width: ranged button (+1) + shouts + racials + off-hand swap (+1).
    local shoutSlots = #shoutAbils + #racialAbils
    local shoutsWidth = (shoutSlots + 2) * BUTTON_SIZE + (shoutSlots + 1) * BUTTON_GAP
    local headerHeight = 24
    local totalHeight = headerHeight + SECTION_GAP + abilitiesHeight + SECTION_GAP + BUTTON_SIZE

    -- Container (drag handle for the whole cluster). Width is the wider of the
    -- ability grid and the bottom row -- a long shouts+racials row (e.g. Undead)
    -- can exceed the 7-wide grid, and we don't want it clipped.
    local container = CreateFrame("Frame", "HelloWarrior_Container", UIParent)
    container:SetSize(math.max(rowWidth, shoutsWidth), totalHeight)
    container:SetMovable(true)
    container:EnableMouse(not HelloWarriorCharDB.locked)  -- locked => not draggable
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if not HelloWarriorCharDB.locked then self:StartMoving() end
    end)
    container:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    -- Faint "move mode" backdrop, shown only while unlocked so the otherwise
    -- transparent cluster is visible and grabbable; drawn behind the buttons.
    local moveBg = container:CreateTexture(nil, "BACKGROUND")
    moveBg:SetAllPoints()
    moveBg:SetColorTexture(0.2, 0.6, 1.0, 0.15)
    if HelloWarriorCharDB.locked then moveBg:Hide() end
    self.moveBg = moveBg
    self.container = container
    self:UpdatePosition()
    if HelloWarriorCharDB.showHWBars == false then container:Hide() end

    -- Melee-range readout: a coloured word centred just above the cluster.
    -- Parented to the container so it drags with it; updated in AB:Tick.
    local rangeText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rangeText:SetPoint("BOTTOM", container, "TOP", 0, SECTION_GAP)
    self.rangeText = rangeText

    -- Abilities bar (secure handler for role swap).
    local bar = CreateFrame("Frame", "HelloWarrior_AbilityBar", container, "SecureHandlerStateTemplate")
    bar:SetSize(rowWidth, abilitiesHeight)
    -- Anchored by TOP so the grid stays centred even when the container is wider
    -- than the grid (long bottom row).
    bar:SetPoint("TOP", container, "TOP", 0, -(headerHeight + SECTION_GAP + BUTTON_SIZE + SECTION_GAP))
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

    bar:SetAttribute("UpdateRole", [[
        local effective = self:GetAttribute("baseRole") or "dps"
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
        -- Set effectiveRole LAST: the insecure OnAttributeChanged hook it fires
        -- (-> OnRoleApplied -> Relayout) must see the settled Show/Hide state.
        self:SetAttribute("effectiveRole", effective)
    ]])

    bar:HookScript("OnAttributeChanged", function(self, name, value)
        if name and name:lower() == "effectiverole" then
            AB:OnRoleApplied(value)
        end
    end)
    -- Role is swapped only by the RoleToggle button now (no hold-Alt overlay) --
    -- Alt is freed for the shout-bar keybindings.

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

    -- Append the player's race racials after the shouts. They join
    -- self.shoutButtons, so Relayout, the cooldown ticker, and keybind positions
    -- all treat them exactly like shouts (off-GCD, no flash, no /startattack).
    -- buildMacro is called with no role, so they get a bare "#showtooltip /cast".
    for ri, ab in ipairs(racialAbils) do
        local prev = self.shoutButtons[#self.shoutButtons]
        local btn = createAbilityButton(shouts, "Racial" .. ri)
        btn:SetPoint("LEFT", prev or ranged, "RIGHT", BUTTON_GAP, 0)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", buildMacro(ab))
        applyAbilityToButton(btn, ab)
        self.shoutButtons[#self.shoutButtons + 1] = btn
    end

    -- Off-hand swap toggle, last on the bottom row. It joins self.shoutButtons
    -- so Relayout, the keybind positions, and the hotkey labels treat it exactly
    -- like a shout/racial -- but it carries NO currentAbility, so the Tick
    -- spell-loop and RefreshLayout both skip it (its icon is driven by
    -- AB:UpdateSwap on inventory changes instead). The macro is a single
    -- /equipslot line; AB:RefreshSwap fills it from the saved set, out of combat.
    do
        local prev = self.shoutButtons[#self.shoutButtons]
        local swap = createAbilityButton(shouts, "OffhandSwap")
        swap:SetPoint("LEFT", prev or ranged, "RIGHT", BUTTON_GAP, 0)
        swap:SetAttribute("type", "macro")
        swap.stanceCorner:Hide()
        swap:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Off-hand swap", 1, 1, 1)
            local s = HelloWarriorCharDB.offhandSwap
            if s and s.weapon and s.shield then
                if IsEquippedItemType("Shields") then
                    GameTooltip:AddLine("Press to swap to: " .. s.weapon.name .. " (dual-wield)", 0.6, 0.85, 1)
                else
                    GameTooltip:AddLine("Press to swap to: " .. s.shield.name .. " (shield)", 0.6, 0.85, 1)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Off-hand weapon: " .. s.weapon.name, 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Shield: " .. s.shield.name, 0.7, 0.7, 0.7)
            else
                GameTooltip:AddLine("Equip your off-hand weapon and type /hw swap,", 0.7, 0.7, 0.7)
                GameTooltip:AddLine("then equip your shield and /hw swap again.", 0.7, 0.7, 0.7)
                if s and s.weapon then GameTooltip:AddLine("Saved off-hand weapon: " .. s.weapon.name, 0.6, 0.8, 0.6) end
                if s and s.shield then GameTooltip:AddLine("Saved shield: " .. s.shield.name, 0.6, 0.8, 0.6) end
            end
            GameTooltip:Show()
        end)
        self.swapButton = swap
        self.shoutButtons[#self.shoutButtons + 1] = swap
    end
    self:RefreshSwap()
    self:UpdateSwap()

    -- Header row: stance indicator + role toggle.
    ns.StanceIndicator:Build(container)
    ns.StanceIndicator.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    ns.RoleToggle:Build(container, bar)
    ns.RoleToggle.frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -1)

    -- Swing timer, in the header row between the stance buttons and role toggle.
    ns.SwingTimer:Build(container, SECTION_GAP)

    -- Rage bar: shares the header band with the swing timer (between the stance
    -- buttons and the role toggle). Rage takes the TOP half (always shown), the
    -- swing timer the bottom half (combat only); each 12px fills the 24px header.
    -- StanceIndicator/RoleToggle are built just above, so their frames exist.
    -- Updated each tick (UNIT_POWER_UPDATE drives Tick too, so it tracks live).
    local rageBar = CreateFrame("StatusBar", "HelloWarrior_RageBar", container)
    rageBar:SetHeight(HEADER_BAR_HEIGHT)
    rageBar:SetPoint("LEFT", ns.StanceIndicator.frame, "RIGHT", SECTION_GAP, 6)
    rageBar:SetPoint("RIGHT", ns.RoleToggle.frame, "LEFT", -SECTION_GAP, 6)
    rageBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rageBar:SetStatusBarColor(RAGE_BASE_COLOR[1], RAGE_BASE_COLOR[2], RAGE_BASE_COLOR[3])  -- rage red
    rageBar:SetMinMaxValues(0, 100)
    local rageBg = rageBar:CreateTexture(nil, "BACKGROUND")
    rageBg:SetAllPoints()
    rageBg:SetColorTexture(0, 0, 0, 0.55)
    local rageLabel = rageBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rageLabel:SetPoint("CENTER")
    self.rageBar = rageBar
    self.rageLabel = rageLabel

    -- Push the initial role through the snippet (out of combat).
    bar:Execute([[ self:RunAttribute("UpdateRole") ]])
    AB:OnRoleApplied(bar:GetAttribute("effectiveRole") or HelloWarriorCharDB.role or "dps")

    self:ResolveMeleeRef()  -- pick the melee-range reference spell for the indicator

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

-- ---- Off-hand swap (dual-wield <-> shield) --------------------------------
-- One secure button toggles slot 17 between a saved off-hand weapon and a saved
-- shield. The macro is a SINGLE /equipslot line whose target item is chosen by
-- ONE [equipped:Shields] check, so it reads the live equipped state exactly once
-- (no mid-macro "bounce" from re-checking after an equip) and the SAME static
-- text toggles both directions -- meaning no in-combat SetAttribute and no
-- addon-side state machine. Swapping only the off-hand leaves the main hand (and
-- its swing timer) untouched. The [equipped:Shields] token is the same item
-- subtype used by IsEquippedItemType("Shields") elsewhere and by the ranged
-- button's [worn:...] conditionals, so it resolves on this client.

-- (Re)build the secure macrotext from the saved set. Out of combat only
-- (SetAttribute on a secure button is blocked under combat lockdown); re-runs
-- from RefreshLayout on PLAYER_REGEN_ENABLED, so a save attempted in combat
-- lands once the fight ends.
function AB:RefreshSwap()
    local btn = self.swapButton
    if not btn then return end
    if InCombatLockdown() then return end
    local s = HelloWarriorCharDB.offhandSwap
    if s and s.weapon and s.shield then
        -- Conditional FIRST (like every other macro here), and the slot is part
        -- of each clause's argument: shield on -> equip the weapon to 17, else
        -- equip the shield to 17. One evaluation, one equip -> no bounce.
        btn:SetAttribute("macrotext",
            ("/equipslot [equipped:Shields] %d %s; %d %s"):format(
                OFFHAND_SLOT, s.weapon.name, OFFHAND_SLOT, s.shield.name))
    else
        btn:SetAttribute("macrotext", "")  -- not configured yet: a no-op press
    end
end

-- Icon/desaturation follow the live equipped state: show the item you'll swap
-- TO (the opposite of what's on now). Purely cosmetic (no Show/Hide, no secure
-- calls), so it's safe in combat -- and UNIT_INVENTORY_CHANGED fires right after
-- a press, flipping the glyph to the new target.
function AB:UpdateSwap()
    local btn = self.swapButton
    if not btn then return end
    local s = HelloWarriorCharDB.offhandSwap
    if s and s.weapon and s.shield then
        local target = IsEquippedItemType("Shields") and s.weapon or s.shield
        btn.icon:SetTexture(target.icon or SWAP_EMPTY_ICON)
        btn.icon:SetDesaturated(false)
    else
        btn.icon:SetTexture(SWAP_EMPTY_ICON)
        btn.icon:SetDesaturated(true)  -- dim until both ends are saved
    end
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- SetTexture resets coords
end

-- Snapshot whatever is currently in the off-hand into the swap set, classifying
-- it as the shield or the off-hand weapon (only slot 17 can hold a shield, so
-- IsEquippedItemType("Shields") tells the two apart). Run it twice -- once with
-- each item equipped -- to define both ends of the toggle. /equipslot takes an
-- item NAME (parsed from the link); the texture is cached for the button glyph.
function AB:SaveOffhandSwap()
    local link = GetInventoryItemLink("player", OFFHAND_SLOT)
    if not link then
        print("|cffc79c6eHelloWarrior|r equip your off-hand weapon or shield first, then /hw swap.")
        return
    end
    local name = link:match("%[(.-)%]")
    if not name or name == "" then
        print("|cffc79c6eHelloWarrior|r couldn't read the off-hand item name; try /hw swap again.")
        return
    end
    local icon = GetInventoryItemTexture("player", OFFHAND_SLOT)
    HelloWarriorCharDB.offhandSwap = HelloWarriorCharDB.offhandSwap or {}
    local s = HelloWarriorCharDB.offhandSwap
    if IsEquippedItemType("Shields") then
        s.shield = { name = name, icon = icon }
        print(("|cffc79c6eHelloWarrior|r saved shield: %s"):format(name))
    else
        s.weapon = { name = name, icon = icon }
        print(("|cffc79c6eHelloWarrior|r saved off-hand weapon: %s"):format(name))
    end
    if s.weapon and s.shield then
        print(("|cffc79c6eHelloWarrior|r off-hand swap ready: %s <-> %s."):format(s.weapon.name, s.shield.name))
    else
        print(("|cffc79c6eHelloWarrior|r now equip your %s and /hw swap again."):format(
            s.shield and "off-hand weapon" or "shield"))
    end
    self:RefreshSwap()
    self:UpdateSwap()
end

function AB:ClearOffhandSwap()
    HelloWarriorCharDB.offhandSwap = nil
    self:RefreshSwap()
    self:UpdateSwap()
    print("|cffc79c6eHelloWarrior|r off-hand swap cleared.")
end

function AB:SetHWBarsVisible(visible)
    if InCombatLockdown() then
        print("|cffc79c6eHelloWarrior|r can't toggle bars in combat.")
        return
    end
    HelloWarriorCharDB.showHWBars = visible and true or false
    if not self.container then return end
    if visible then self.container:Show() else self.container:Hide() end
    -- Sync the keybind overrides to the new visibility: off clears them (keys
    -- fall back to their normal action), on re-applies them.
    if ns.Keybinds then ns.Keybinds:Apply() end
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
    self:Relayout()
    self:Tick()
end

-- Place `btns` left-to-right from xStart, anchored to `parent`.
local function placeRow(btns, parent, xStart, y)
    for i, btn in ipairs(btns) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT",
            xStart + (i - 1) * (BUTTON_SIZE + BUTTON_GAP), y)
    end
end

local function rowSpan(n)
    if n <= 0 then return 0 end
    return n * BUTTON_SIZE + (n - 1) * BUTTON_GAP
end

-- Collapse the gaps left by hidden buttons and centre each (partial) row. These
-- are secure buttons, so SetPoint is illegal in combat: this no-ops during
-- combat and re-runs on the next role/talent change or PLAYER_REGEN_ENABLED.
function AB:Relayout()
    if InCombatLockdown() then return end

    -- Ability grid. DPS auto-wraps at ABILITIES_PER_ROW; tank uses explicit rows
    -- (A.tankRows) so its row breaks are fixed regardless of which talents show.
    if self.buttons and self.bar then
        local fullWidth = rowSpan(ABILITIES_PER_ROW)
        local rowIdx = 0
        local function emit(row)
            if #row > 0 then
                placeRow(row, self.bar, (fullWidth - rowSpan(#row)) / 2,
                    -rowIdx * (BUTTON_SIZE + ROW_GAP))
                rowIdx = rowIdx + 1
            end
        end
        local role = self.bar:GetAttribute("effectiveRole") or HelloWarriorCharDB.role or "dps"
        local explicit = (role == "tank") and ns.Abilities.tankRows or nil
        if explicit then
            -- Each defined row collapses its own hidden buttons and centres the rest.
            local dataIdx = 1
            for _, size in ipairs(explicit) do
                local row = {}
                for k = dataIdx, dataIdx + size - 1 do
                    local b = self.buttons[k]
                    if b and b:IsShown() then row[#row + 1] = b end
                end
                emit(row)
                dataIdx = dataIdx + size
            end
        else
            local vis = {}
            for _, b in ipairs(self.buttons) do
                if b:IsShown() then vis[#vis + 1] = b end
            end
            local i = 1
            while i <= #vis do
                local n = math.min(ABILITIES_PER_ROW, #vis - i + 1)
                local row = {}
                for c = 0, n - 1 do row[c + 1] = vis[i + c] end
                emit(row)
                i = i + n
            end
        end
    end

    -- Shouts row: ranged button + visible shouts, centred in the shouts bar.
    if self.shoutsBar then
        local vis = {}
        if self.rangedButton and self.rangedButton:IsShown() then
            vis[#vis + 1] = self.rangedButton
        end
        for _, b in ipairs(self.shoutButtons or {}) do
            if b:IsShown() then vis[#vis + 1] = b end
        end
        if #vis > 0 then
            placeRow(vis, self.shoutsBar,
                (self.shoutsBar:GetWidth() - rowSpan(#vis)) / 2, 0)
        end
    end

    -- Re-bind position->button keybindings and repaint hotkey labels now that
    -- the visible layout is settled (out of combat; SetOverrideBindingClick is
    -- combat-protected). Runs on login, role swap, talent change, and regen.
    if ns.Keybinds then
        ns.Keybinds:Apply()
        ns.Keybinds:RefreshLabels()
    end
end

-- Clear the cooldown sweep AND reset the guard, so the two stay in sync. Routing
-- every clear through here means a slot that goes valid->invalid->valid within
-- one cooldown window can't strand the guard (which would otherwise see an
-- unchanged start and skip re-showing the sweep).
local function clearCooldown(btn)
    if btn._cdStart ~= 0 then
        btn.cooldown:Clear()
        btn._cdStart, btn._cdDuration = 0, 0
    end
end

local function updateCooldown(btn, spellName)
    local start, duration = GetSpellCooldown(spellName)
    -- Show EVERY cooldown, including the 1.5s GCD, so the buttons sweep together
    -- like the default action bars (the old `duration > 1.5` guard filtered the
    -- GCD out, which is why there was no GCD animation). SetCooldown is keyed off
    -- the absolute start time, so re-calling it each 0.1s tick with unchanged
    -- values doesn't restart the sweep; we still guard to avoid needless churn.
    if start and duration and start > 0 and duration > 0 then
        if btn._cdStart ~= start or btn._cdDuration ~= duration then
            btn.cooldown:SetCooldown(start, duration)
            btn._cdStart, btn._cdDuration = start, duration
        end
    else
        clearCooldown(btn)
    end
end

-- Resolve once: bare global on 1.15.x, C_Spell on newer-API clients (the latter
-- returns a boolean, normalized below). Mirrors the isCurrentSpell pattern.
local IsSpellInRange = IsSpellInRange or (C_Spell and C_Spell.IsSpellInRange)

-- 0 = out of range, 1 = in range, nil = no range check applies (no/invalid or
-- friendly/dead target, self-buff/shout, unknown spell). nil must NEVER read as
-- out of range, so callers key strictly off `== 0`. Works the same everywhere,
-- including dungeons and raids -- it's a pure target-range check, not zone-gated.
local function spellRange(spellName)
    if not IsSpellInRange then return nil end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then return nil end
    local r = IsSpellInRange(spellName, "target")
    if r == true then return 1 elseif r == false then return 0 end
    return r
end

local function updateRageTint(btn, spellName)
    local usable, noPower = IsUsableSpell(spellName)
    if not usable and noPower then
        btn.icon:SetVertexColor(0.6, 0.6, 0.9)        -- rage-starved (blue)
    elseif not usable then
        btn.icon:SetVertexColor(0.4, 0.4, 0.4)        -- unusable / wrong stance (grey)
    elseif spellRange(spellName) == 0 then
        btn.icon:SetVertexColor(0.9, 0.35, 0.35)      -- castable but OUT OF RANGE (red)
    else
        btn.icon:SetVertexColor(1, 1, 1)              -- usable & in range / range N/A (white)
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
            ns:SetShine(btn, ab.onNextSwing and isQueued(ab.name), 0.45, 0.8, 1.0)
        else
            clearCooldown(btn)
            applyFlash(btn, {})
            ns:SetShine(btn, false)
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

    self:UpdateRangeIndicator()
    self:UpdateRageBar()
end

-- Melee reference for the range readout, first-known-wins. These are normal
-- TARGETED melee abilities whose GetSpellInfo reports a real ~5yd range, so
-- IsSpellInRange returns a usable 1/0 (the per-button red tint already proves
-- this works for them). Heroic Strike / Cleave are NOT here: they're on-next-
-- swing and IsSpellInRange returns nil for them -- gating on Heroic Strike was
-- the original blank-indicator bug. Sunder Armor leads: it's any-stance, so its
-- range check is reliable regardless of the stance you're in.
local MELEE_REF_CANDIDATES = { "Sunder Armor", "Rend", "Hamstring", "Mortal Strike", "Pummel" }

function AB:ResolveMeleeRef()
    self.meleeRefSpell = nil
    for _, name in ipairs(MELEE_REF_CANDIDATES) do
        if GetSpellInfo(name) then  -- non-nil == learned by this character
            self.meleeRefSpell = name
            return
        end
    end
end

-- Melee-range readout above the cluster: green MELEE when the target is in melee,
-- gold CHARGE when out of melee but within Charge range, red OUT otherwise, blank
-- with no attackable target (or before any melee reference is learned). Range is
-- hitbox-aware (IsSpellInRange of a real targeted melee ability, so it reads
-- correctly on large bosses); no yard number is obtainable for an enemy. The
-- Charge band degrades to OUT if its check is unavailable (Charge is Battle-
-- stance-restricted and can read nil otherwise).
function AB:UpdateRangeIndicator()
    local t = self.rangeText
    if not t then return end
    local ref = self.meleeRefSpell
    if not ref then self:ResolveMeleeRef(); ref = self.meleeRefSpell end
    local m = ref and spellRange(ref) or nil
    if m == nil then
        t:SetText("")
    elseif m == 1 then
        t:SetText("MELEE")
        t:SetTextColor(0.35, 0.9, 0.45)
    elseif spellRange("Charge") == 1 then
        t:SetText("CHARGE")
        t:SetTextColor(1.0, 0.82, 0.0)
    else
        t:SetText("OUT")
        t:SetTextColor(0.9, 0.35, 0.35)
    end
end

-- Rage bar fill + number. UnitPowerMax is 100 baseline (guarded if it ever
-- reads 0 before data loads).
function AB:UpdateRageBar()
    local b = self.rageBar
    if not b then return end
    local cur = UnitPower("player", RAGE_POWER_TYPE)
    local max = UnitPowerMax("player", RAGE_POWER_TYPE)
    if not max or max == 0 then max = 100 end
    b:SetMinMaxValues(0, max)
    b:SetValue(cur)
    self.rageLabel:SetText(cur)
    self:UpdateRageWarn()
end

-- Throb the rage bar's colour while near cap (in combat). The throb runs on the
-- bar's own OnUpdate for a smooth per-frame lerp, independent of the 0.1s ticker;
-- a _rageWarnOn guard installs/removes it only on the on<->off transition (like
-- the shine cue), and the off path restores the resting red. OnUpdate doesn't
-- fire while the cluster is hidden, so a hidden bar costs nothing.
function AB:UpdateRageWarn()
    local b = self.rageBar
    if not b then return end
    local warn = ns.Helper:IsRageCapping()
    if warn then
        if not b._rageWarnOn then
            b._rageWarnOn = true
            b._rageWarnT = 0
            b:SetScript("OnUpdate", function(self, elapsed)
                self._rageWarnT = (self._rageWarnT or 0) + elapsed
                local cycle = (self._rageWarnT / RAGE_WARN_PERIOD) % 2
                local p = cycle <= 1 and cycle or (2 - cycle)
                self:SetStatusBarColor(
                    RAGE_BASE_COLOR[1] + (RAGE_WARN_COLOR[1] - RAGE_BASE_COLOR[1]) * p,
                    RAGE_BASE_COLOR[2] + (RAGE_WARN_COLOR[2] - RAGE_BASE_COLOR[2]) * p,
                    RAGE_BASE_COLOR[3] + (RAGE_WARN_COLOR[3] - RAGE_BASE_COLOR[3]) * p)
            end)
        end
    elseif b._rageWarnOn then
        b._rageWarnOn = false
        b:SetScript("OnUpdate", nil)
        b:SetStatusBarColor(RAGE_BASE_COLOR[1], RAGE_BASE_COLOR[2], RAGE_BASE_COLOR[3])
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
    self:RefreshSwap()  -- (re)apply the off-hand swap macro out of combat
    self:Relayout()
end

ns:On("PLAYER_LOGIN", function()
    if not ns.enabled then return end
    AB:Build()
end)
ns:On("SPELLS_CHANGED",      function() AB:ResolveMeleeRef(); AB:RefreshLayout() end)
ns:On("PLAYER_REGEN_ENABLED", function() AB:RefreshLayout() end)
ns:On("PLAYER_ENTERING_WORLD",       function() AB:UpdateRanged(); AB:UpdateSwap() end)
ns:On("UNIT_INVENTORY_CHANGED", function(unit)
    if unit == "player" then AB:UpdateRanged(); AB:UpdateSwap() end
end)
ns:On("UPDATE_SHAPESHIFT_FORM", function()
    maybePressFlash()
    AB:Tick()
end)
ns:On("UNIT_POWER_UPDATE", function(unit)
    if unit == "player" then AB:Tick() end
end)
ns:On("PLAYER_TARGET_CHANGED", function() AB:Tick() end)
-- Fires when an on-next-swing ability (Heroic Strike / Cleave) is queued, fires,
-- or is cancelled -- refresh the queued-glow immediately instead of waiting for
-- the 0.1s ticker.
ns:On("CURRENT_SPELL_CAST_CHANGED", function() AB:Tick() end)
-- Interrupt alert: snap the Pummel/Shield Bash flash on/off when the target
-- starts/stops a cast or channel. These events are unreliable for unit=="target"
-- on Classic Era, so they're only low-latency hints -- the 0.1s ticker polling
-- UnitCastingInfo("target") is the source of truth (and PLAYER_TARGET_CHANGED
-- above catches switching to a target already mid-cast).
local function onTargetCast(unit)
    if unit == "target" then AB:Tick() end
end
for _, e in ipairs({
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED",
}) do
    ns:On(e, onTargetCast)
end
