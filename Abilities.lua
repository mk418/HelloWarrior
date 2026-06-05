local ADDON_NAME, ns = ...

ns.Abilities = {}
local A = ns.Abilities

-- Stance IDs match GetShapeshiftForm() return values in Classic.
A.STANCE_ID = { battle = 1, defensive = 2, berserker = 3 }
A.STANCE_SPELL = { [1] = "Battle Stance", [2] = "Defensive Stance", [3] = "Berserker Stance" }
-- Spell IDs for stances — used to fetch icons even for unlearned stances.
A.STANCE_SPELL_ID = { [1] = 2457, [2] = 71, [3] = 2458 }

-- World buffs that can flip priority (see `prio_when` below).
A.WORLD_BUFFS = {
    DRAGONSLAYER = "Rallying Cry of the Dragonslayer",
    ZANDALAR     = "Spirit of Zandalar",
}

-- Flash rule shapes:
--   { type = "off_cd" }                                  pulse when the spell is off cooldown
--   { type = "rage",     threshold = N }                 pulse when current rage >= N
--   { type = "proc" }                                    pulse while the ability's proc window is open
--                                                         (e.g. Revenge after dodge/block/parry, Overpower after dodge)
--   { type = "target_hp", lt = N }                       pulse when target HP% < N
--   { type = "nodebuff",  spell = "Sunder Armor", stacks = 5 }
--                                                         pulse unless target has N stacks of `spell`
--   { type = "helper" }                                  Bloodrage; flashed by the rage-helper engine
--   { type = "off_cd", independent = true }              flashes on its own, OUTSIDE the priority queue
--                                                         (an off-GCD button you press whenever it's ready, e.g. Shield Block)
--
-- `prio` (lower = higher priority). Blank prio → soft-flash only, never "optimal".
-- `prio_when` overrides prio when all listed buffs are present on the player.
-- `talentOnly = true` → button is hidden if the spell isn't in the spellbook
--                      (baseline spells the player hasn't reached the level for show desaturated instead).
-- `requiresShield = true` → the ability's flash only fires when a shield is equipped.
-- `stance` is either a string ("any" / "battle" / "defensive" / "berserker")
--          or a list of strings for abilities usable in multiple stances.
--          For multi-stance, the FIRST entry is the default the macro switches into.
-- `mode = "two_press"` opts a button into `[stance:N] Ability; Stance` form
--          (safe-fail, no rage gamble). Default is one-press dance.
-- `combo = { modifier = "shift", use = "ItemName" }` — modifier-click uses an item first.

A.shouts = {
    { name = "Battle Shout",       stance = "any", noStartAttack = true,
      flash = { type = "nobuff", buff = "Battle Shout" } },
    { name = "Demoralizing Shout", stance = "any", noStartAttack = true },
    { name = "Challenging Shout",  stance = "any", noStartAttack = true,
      combo = { modifier = "shift", use = "Limited Invulnerability Potion" } },
    { name = "Intimidating Shout", stance = "any", noStartAttack = true },
    { name = "Piercing Howl",      stance = "any", talentOnly = true, noStartAttack = true },
}

-- Buffs to strip off a warrior. The ability macros /cancelaura these out of
-- combat (Blizzard blocks buff-cancel in combat), so they fall off when you use
-- an ability to engage. `both` = caster/mana blessings wasted on a Rage class;
-- `tank` also drops the Salvation threat-reducers (DPS keep Salvation -- the
-- threat cut lets them push more damage). Single and group buff names are both
-- listed since either form can land on you.
A.unwantedBuffs = {
    both = {
        "Blessing of Wisdom", "Greater Blessing of Wisdom",
        "Arcane Intellect", "Arcane Brilliance",
        "Divine Spirit", "Prayer of Spirit",
    },
    tank = {
        "Blessing of Salvation", "Greater Blessing of Salvation",
    },
}

-- Tank uses an EXPLICIT row layout (see A.tankRows); DPS keeps the auto-wrap.
A.tank = {
    -- Row 1.
    { name = "Revenge",        stance = "defensive", flash = { type = "proc" }, prio = 1 },
    -- Bloodthirst (Fury) / Mortal Strike (Arms) / Shield Slam (Prot) are the
    -- three mutually-exclusive 31-point talents: you can train at most one, so
    -- exactly the one you have shows here and the other two collapse.
    { name = "Bloodthirst",    stance = "any", talentOnly = true,
      flash = { type = "off_cd" }, prio = 3 },
    { name = "Mortal Strike",  stance = "battle", talentOnly = true,
      flash = { type = "off_cd" }, prio = 3 },
    { name = "Shield Slam",    stance = "any", talentOnly = true, requiresShield = true,
      flash = { type = "off_cd" }, prio = 2 },
    { name = "Sunder Armor",   stance = "any",
      flash = { type = "nodebuff", spell = "Sunder Armor", stacks = 5 }, prio = 4 },
    { name = "Heroic Strike",  stance = "any",       flash = { type = "rage", threshold = 50 }, prio = 5 },
    { name = "Cleave",         stance = "any" },
    { name = "Taunt",          stance = "defensive" },
    { name = "Mocking Blow",   stance = "battle" },
    -- Row 2.
    { name = "Shield Bash",    stance = { "defensive", "battle" } },
    { name = "Death Wish",     stance = "any", talentOnly = true, noStartAttack = true },
    { name = "Berserker Rage", stance = "berserker", noStartAttack = true },
    { name = "Disarm",         stance = "defensive" },
    { name = "Concussion Blow", stance = "any", talentOnly = true },
    { name = "Shield Block",   stance = "defensive", requiresShield = true, noStartAttack = true,
      flash = { type = "off_cd", independent = true } },
    -- Row 3.
    { name = "Bloodrage",      stance = "any",       flash = { type = "helper" }, noStartAttack = true },
    { name = "Charge",         stance = "battle", noStartAttack = true },
    { name = "Intercept",      stance = "berserker", noStartAttack = true },
    { name = "Last Stand",     stance = "any", talentOnly = true, noStartAttack = true },
    { name = "Shield Wall",    stance = "defensive", noStartAttack = true },
}

-- Explicit per-row sizes for the tank bar, in A.tank order; must sum to #A.tank.
-- Hidden talents collapse WITHIN their own row, so the rows stay grouped as
-- listed above regardless of spec (DPS instead auto-wraps at ABILITIES_PER_ROW).
-- Row 1 holds 9 entries but only ever shows 7 (two of the three 31-pt talents
-- always collapse), so it still fits the 7-wide bar.
A.tankRows = { 9, 6, 5 }

A.dps = {
    -- Core rotation, highest priority first (leftmost = flashed first).
    { name = "Execute",        stance = { "berserker", "battle" },
      flash = { type = "target_hp", lt = 20 }, prio = 1,
      prio_when = { { buffs = { "Rallying Cry of the Dragonslayer", "Spirit of Zandalar" }, prio = 2 } } },
    -- Bloodthirst (Fury) and Mortal Strike (Arms) are mutually exclusive, so
    -- whichever you've trained shows here and the other's slot collapses away.
    { name = "Bloodthirst",    stance = "any", talentOnly = true,
      flash = { type = "off_cd" }, prio = 2,
      prio_when = { { buffs = { "Rallying Cry of the Dragonslayer", "Spirit of Zandalar" }, prio = 1 } } },
    { name = "Mortal Strike",  stance = "battle", talentOnly = true,
      flash = { type = "off_cd" }, prio = 2 },
    { name = "Whirlwind",      stance = "berserker", flash = { type = "off_cd" }, prio = 3 },
    { name = "Overpower",      stance = "battle",    flash = { type = "proc" },   prio = 3 },
    { name = "Sunder Armor",   stance = "any",
      flash = { type = "nodebuff", spell = "Sunder Armor", stacks = 5 }, prio = 4 },
    { name = "Heroic Strike",  stance = "any",       flash = { type = "rage", threshold = 50 }, prio = 5 },
    { name = "Cleave",         stance = "any" },
    -- Utility / cooldowns.
    { name = "Pummel",         stance = "berserker" },
    { name = "Death Wish",     stance = "any", talentOnly = true, noStartAttack = true },
    { name = "Berserker Rage", stance = "berserker", noStartAttack = true },
    { name = "Disarm",         stance = "defensive" },
    { name = "Hamstring",      stance = { "berserker", "battle" } },
    { name = "Thunder Clap",   stance = "battle" },
    { name = "Slam",           stance = "any" },
    -- Bottom group: rage helper, movement, long cooldowns.
    { name = "Bloodrage",      stance = "any",       flash = { type = "helper" }, noStartAttack = true },
    { name = "Charge",         stance = "battle", noStartAttack = true },
    { name = "Intercept",      stance = "berserker", noStartAttack = true },
    { name = "Retaliation",    stance = "battle", noStartAttack = true },
    { name = "Recklessness",   stance = "berserker", noStartAttack = true },
}
