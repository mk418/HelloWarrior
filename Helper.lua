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

local function evaluateFlash(ability)
    local rule = ability.flash
    if not rule then return false end
    if not GetSpellInfo(ability.name) then return false end  -- not learned

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
        for i = 1, 40 do
            local n = UnitBuff("player", i)
            if not n then break end
            if n == rule.buff then return false end
        end
        return true
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
function Helper:Compute(role)
    local list = (role == "tank") and ns.Abilities.tank or ns.Abilities.dps

    local affordableFlashing = {}
    local optimalAffordable, optAffPrio = nil, math.huge
    local topRuleMet, topRuleMetPrio = nil, math.huge

    for _, ab in ipairs(list) do
        if ab.flash and ab.flash.type ~= "helper" and evaluateFlash(ab) then
            local p = resolvePriority(ab) or math.huge
            if p < topRuleMetPrio then
                topRuleMet, topRuleMetPrio = ab, p
            end
            if isAffordable(ab) then
                affordableFlashing[ab.name] = true
                if p < optAffPrio then
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
        elseif affordableFlashing[ab.name] then
            r.soft = true
            r.hard = (ab == optimalAffordable)
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
