local ADDON_NAME, ns = ...

ns.Helper = {}
local Helper = ns.Helper

local PROC_DURATION = 5
local RAGE_POWER_TYPE = Enum and Enum.PowerType and Enum.PowerType.Rage or 1

-- Proc windows opened by combat-log events (Revenge after dodge/block/parry on
-- the player; Overpower after the target dodges the player's swing).
local procWindow = {}

-- Cached lookups.
local rageCostCache = {}
local tacMasteryRank = 0

local function rageCost(spellName)
    if rageCostCache[spellName] ~= nil then return rageCostCache[spellName] end
    local _, _, _, _, _, _, spellID = GetSpellInfo(spellName)
    local cost = 0
    if spellID and GetSpellPowerCost then
        local costs = GetSpellPowerCost(spellID)
        if costs then
            for _, c in ipairs(costs) do
                if c.type == RAGE_POWER_TYPE then cost = c.cost or 0; break end
            end
        end
    end
    rageCostCache[spellName] = cost
    return cost
end

local function refreshTalents()
    tacMasteryRank = 0
    if not GetNumTalentTabs or not GetNumTalents then return end
    for tab = 1, GetNumTalentTabs() do
        local n = GetNumTalents(tab) or 0
        for i = 1, n do
            local name, _, _, _, rank = GetTalentInfo(tab, i)
            if name == "Tactical Mastery" then
                tacMasteryRank = rank or 0
                return
            end
        end
    end
end

local function currentStanceId() return GetShapeshiftForm() end

local function stanceMatches(ability)
    if not ability.stance or ability.stance == "any" then return true end
    local cur = currentStanceId()
    if type(ability.stance) == "string" then
        return cur == ns.Abilities.STANCE_ID[ability.stance]
    end
    for _, s in ipairs(ability.stance) do
        if cur == ns.Abilities.STANCE_ID[s] then return true end
    end
    return false
end

local function rageAfterSwitch()
    local cur = UnitPower("player", RAGE_POWER_TYPE)
    return math.min(cur, tacMasteryRank * 5)
end

local function isOffCooldown(spellName)
    local start, duration = GetSpellCooldown(spellName)
    if not start or not duration then return true end
    if duration <= 1.5 then return true end  -- GCD only
    return (start + duration - GetTime()) <= 0
end

local function hasAllBuffs(buffNames)
    for _, target in ipairs(buffNames) do
        local found = false
        for i = 1, 40 do
            local n = UnitBuff("player", i)
            if not n then break end
            if n == target then found = true; break end
        end
        if not found then return false end
    end
    return true
end

local function targetDebuffStacks(spellName)
    if not UnitExists("target") then return 0 end
    for i = 1, 40 do
        local n, _, count = UnitDebuff("target", i, "PLAYER")
        if not n then break end
        if n == spellName then return count or 1 end
    end
    return 0
end

local function resolvePriority(ability)
    if ability.prio_when then
        for _, override in ipairs(ability.prio_when) do
            if override.buffs and hasAllBuffs(override.buffs) then return override.prio end
        end
    end
    return ability.prio
end

local function shieldEquipped()
    return IsEquippedItemType and IsEquippedItemType("Shields") or false
end

-- Remaining seconds on a named HELPFUL aura on the player: math.huge if present
-- without a running duration, nil if absent. Reads the AuraData NAMED fields
-- (no positional-return ambiguity -- the legacy UnitBuff tuple varies by client)
-- via C_UnitAuras, falling back to a name-only UnitBuff scan (presence only) if
-- that API is missing.
local GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local function playerBuffRemaining(buffName)
    if GetAuraDataByIndex then
        for i = 1, 40 do
            local aura = GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            if aura.name == buffName then
                local exp = aura.expirationTime
                if exp and exp > 0 then return exp - GetTime() end
                return math.huge
            end
        end
        return nil
    end
    for i = 1, 40 do
        local n = UnitBuff("player", i)
        if not n then break end
        if n == buffName then return math.huge end
    end
    return nil
end

-- True when the current (attackable) target is mid-cast/channel and it's
-- interruptible. `notInterruptible` sits at a DIFFERENT position per API on
-- Classic Era 1.15.x -- 8th return for UnitCastingInfo (after castID), 7th for
-- UnitChannelInfo (channels have no castID) -- so the two are read separately.
-- The flag is effectively always nil for hostile NPC casts on 1.15.x, so this
-- fails OPEN (any target cast counts as interruptible) -- the right vanilla
-- default; we still honour an explicit `true` ("skip"). Note UnitChannelInfo
-- returns nil for non-player units on 1.15.x, so target channels may not detect.
local function targetCastingInterruptible()
    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        return false
    end
    local castName, _, _, _, _, _, _, castNotInterruptible = UnitCastingInfo("target")
    if castName then return not castNotInterruptible end
    local chanName, _, _, _, _, _, chanNotInterruptible = UnitChannelInfo("target")
    if chanName then return not chanNotInterruptible end
    return false
end

local function evaluateFlash(ability)
    local rule = ability.flash
    if not rule then return false end
    if not GetSpellInfo(ability.name) then return false end  -- not learned
    if ability.requiresShield and not shieldEquipped() then return false end

    local t = rule.type
    if t == "off_cd" then
        return isOffCooldown(ability.name)
    elseif t == "rage" then
        return UnitPower("player", RAGE_POWER_TYPE) >= (rule.threshold or 0)
    elseif t == "proc" then
        local exp = procWindow[ability.name]
        return exp and exp > GetTime() or false
    elseif t == "target_hp" then
        if not UnitExists("target") or UnitIsDead("target") then return false end
        local mx = UnitHealthMax("target")
        if mx == 0 then return false end
        return (UnitHealth("target") / mx) * 100 < (rule.lt or 0)
    elseif t == "nodebuff" then
        return targetDebuffStacks(rule.spell) < (rule.stacks or 1)
    elseif t == "nobuff" then
        -- Flash when the buff is absent, or (with `refresh = N`) when it has N
        -- seconds or less remaining -- a "recast soon" reminder.
        local remaining = playerBuffRemaining(rule.buff)
        if remaining == nil then return true end
        if rule.refresh then return remaining <= rule.refresh end
        return false
    elseif t == "interrupt" then
        -- Flash only while the target is mid-interruptible-cast AND the interrupt
        -- is actually ready. The off-cooldown gate matters because these spells
        -- cost no rage the engine sees (isAffordable is trivially true), so the
        -- independent-flash path would otherwise light up mid-cooldown.
        return targetCastingInterruptible() and isOffCooldown(ability.name)
    end
    return false
end

local function isAffordable(ability)
    local cost = rageCost(ability.name)
    if cost <= 0 then return true end
    if stanceMatches(ability) then
        return UnitPower("player", RAGE_POWER_TYPE) >= cost
    end
    return rageAfterSwitch() >= cost
end

-- Compute flash results for every ability in the active role list.
-- An ability flashes only if its rule fires AND you can actually cast it now
-- (rage post-stance-switch). The Bloodrage helper flashes when the would-be
-- top-priority rule-met ability is unaffordable, regardless of whether it's
-- a current candidate.
-- True when you're near the rage cap IN COMBAT -- the single shared trigger for
-- the rage-cap warning. Both the rage bar throb (ActionBar) and the rage-dump
-- cue below (Heroic Strike / Cleave light up) read this, so the bar and the
-- buttons light together. Max rage is 100 on Classic Era, but we drive it off
-- UnitPowerMax to be safe.
local RAGE_CAP_FRACTION = 0.80
function Helper:IsRageCapping()
    if not InCombatLockdown() then return false end
    local max = UnitPowerMax("player", RAGE_POWER_TYPE)
    if not max or max == 0 then return false end
    return (UnitPower("player", RAGE_POWER_TYPE) / max) >= RAGE_CAP_FRACTION
end

function Helper:Compute(role)
    local list = (role == "tank") and ns.Abilities.tank or ns.Abilities.dps
    local rageCapping = self:IsRageCapping()

    local affordableFlashing = {}
    local optimalAffordable, optAffPrio = nil, math.huge
    local topRuleMet, topRuleMetPrio = nil, math.huge

    for _, ab in ipairs(list) do
        if ab.flash and ab.flash.type ~= "helper" and not ab.flash.independent and evaluateFlash(ab) then
            local p = resolvePriority(ab) or math.huge
            -- On-next-swing abilities (Heroic Strike / Cleave) are off the GCD:
            -- you queue them in PARALLEL with a GCD press, not instead of one. So
            -- they keep their soft "you've got the rage, queue it" flash below,
            -- but never win the gold "optimal" ring (which is the best GCD press)
            -- nor trigger the Bloodrage helper. This keeps Bloodthirst/Sunder the
            -- recommendation rather than Heroic Strike.
            local rotational = not ab.onNextSwing
            if rotational and p < topRuleMetPrio then
                topRuleMet, topRuleMetPrio = ab, p
            end
            if isAffordable(ab) then
                affordableFlashing[ab.name] = true
                if rotational and p < optAffPrio then
                    optimalAffordable, optAffPrio = ab, p
                end
            end
        end
    end

    local bloodrageFlash = false
    if topRuleMet and not isAffordable(topRuleMet)
       and isOffCooldown("Bloodrage") and GetSpellInfo("Bloodrage") then
        bloodrageFlash = true
    end

    local results = {}
    for _, ab in ipairs(list) do
        local r = { soft = false, hard = false }
        if ab.flash and ab.flash.type == "helper" then
            r.soft = bloodrageFlash
            r.hard = bloodrageFlash
        elseif ab.flash and ab.flash.independent then
            -- Off-GCD "press whenever ready" flash, outside the priority queue,
            -- but only when you can actually afford it.
            local on = evaluateFlash(ab) and isAffordable(ab)
            r.soft = on
            r.hard = on
        elseif affordableFlashing[ab.name] then
            r.soft = true
            r.hard = (ab == optimalAffordable)
        end
        -- Rage-cap dump: near the rage cap in combat, the rage-dump abilities
        -- (Heroic Strike / Cleave) light up HARD so you spend the excess into
        -- them. They're off the GCD, so this is ADDITIVE to whatever GCD ability
        -- is optimal -- both can glow at once (press the GCD pick, queue the
        -- dump). Only when learned and affordable (at >=80% rage you can be sure).
        if rageCapping and ab.rageDump and GetSpellInfo(ab.name) and isAffordable(ab) then
            r.soft = true
            r.hard = true
        end
        results[ab.name] = r
    end

    -- Shouts: evaluated independently of role priority.
    for _, ab in ipairs(ns.Abilities.shouts) do
        if ab.flash and evaluateFlash(ab) then
            results[ab.name] = { soft = true, hard = true }
        end
    end

    return results
end

local function handleCombatLog()
    local args = { CombatLogGetCurrentEventInfo() }
    local subevent = args[2]
    if not subevent then return end
    local sourceGUID, destGUID = args[4], args[8]
    local playerGUID = UnitGUID("player")
    local targetGUID = UnitGUID("target")

    local missType
    if subevent == "SWING_MISSED" then
        missType = args[12]
    elseif subevent == "SPELL_MISSED" or subevent == "RANGE_MISSED" then
        missType = args[15]
    else
        return
    end

    if destGUID == playerGUID and (missType == "DODGE" or missType == "PARRY" or missType == "BLOCK") then
        procWindow["Revenge"] = GetTime() + PROC_DURATION
    end
    if sourceGUID == playerGUID and targetGUID and destGUID == targetGUID and missType == "DODGE" then
        procWindow["Overpower"] = GetTime() + PROC_DURATION
    end
end

ns:On("COMBAT_LOG_EVENT_UNFILTERED", handleCombatLog)
ns:On("PLAYER_TALENT_UPDATE", refreshTalents)
ns:On("CHARACTER_POINTS_CHANGED", refreshTalents)
ns:On("SPELLS_CHANGED", function() wipe(rageCostCache) end)
ns:On("PLAYER_LOGIN", function()
    if not ns.enabled then return end
    refreshTalents()
end)
