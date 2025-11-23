-- SmartSealAttack.lua
-- Helper for Paladins: combat automation for Ret/Support plus Holy healer mode.

local SEAL_NAME                   = "Seal of Righteousness"
local SEAL_OF_COMMAND_NAME        = "Seal of Command"
local SEAL_OF_LIGHT_NAME          = "Seal of Light"
local SEAL_OF_WISDOM_NAME         = "Seal of Wisdom"
local AURA_NAME                   = "Devotion Aura"
local CONCENTRATION_AURA_NAME     = "Concentration Aura"
local BLESSING_MIGHT_NAME         = "Blessing of Might"
local BLESSING_WISDOM_NAME        = "Blessing of Wisdom"
local BLESSING_SALVATION_NAME     = "Blessing of Salvation"
local BLESSING_KINGS_NAME         = "Blessing of Kings"
local JUDGEMENT_NAME              = "Judgement"
local JUDGEMENT_DEBUFF_NAME       = "Judgement of Righteousness"
local HAMMER_NAME                 = "Hammer of Justice"
local HAMMER_DEBUFF_NAME          = "Hammer of Justice"
local DIVINE_PROTECTION_NAME      = "Divine Protection"
local HOLY_LIGHT_NAME             = "Holy Light"
local FLASH_OF_LIGHT_NAME         = "Flash of Light"
local HOLY_SHOCK_NAME             = "Holy Shock"

local MODES = {
    RET = "ret",
    SUPPORT = "support",
    HEALER = "healer",
}

local currentMode = MODES.RET

-- What blessing this paladin is assigned to keep up in healer mode.
-- Options: "wisdom", "might", "salvation", "kings"
local assignedBlessing = "wisdom"

-- Put your "Attack" ability on this action slot (1 = bottom-left first button)
local ATTACK_ACTION_SLOT = 1

local BLESSING_BY_KEY = {
    might = BLESSING_MIGHT_NAME,
    wisdom = BLESSING_WISDOM_NAME,
    salvation = BLESSING_SALVATION_NAME,
    kings = BLESSING_KINGS_NAME,
}

-------------------------------------------------------
-- Generic tooltip-based buff/debuff checks
-------------------------------------------------------
local function HasBuffByName(unit, wantedName)
    for i = 1, 40 do
        local tex = UnitBuff(unit, i)
        if not tex then
            break
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:ClearLines()
        GameTooltip:SetUnitBuff(unit, i)

        local buffName = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() or nil
        if buffName == wantedName then
            return true
        end
    end
    return false
end

local function HasDebuffByName(unit, wantedName)
    for i = 1, 40 do
        local tex = UnitDebuff(unit, i)
        if not tex then
            break
        end

        GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        GameTooltip:ClearLines()
        GameTooltip:SetUnitDebuff(unit, i)

        local debuffName = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText() or nil
        if debuffName == wantedName then
            return true
        end
    end
    return false
end

-------------------------------------------------------
-- Spellbook helpers
-------------------------------------------------------
local spellIndexCache = {}

local function FindSpellIndex(spellName)
    if spellIndexCache[spellName] then
        return spellIndexCache[spellName]
    end
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = 1, numSpells do
            local spellIndex = offset + i
            local name = GetSpellName(spellIndex, "spell")
            if name == spellName then
                spellIndexCache[spellName] = spellIndex
                return spellIndex
            end
        end
    end
    return nil
end

local function IsSpellKnown(spellName)
    return FindSpellIndex(spellName) ~= nil
end

local function IsSpellReady(spellName)
    local idx = FindSpellIndex(spellName)
    if not idx then return false end
    local start, duration, enabled = GetSpellCooldown(idx, "spell")
    if not start or enabled == 0 then return false end
    if duration == 0 then return true end
    return (start + duration - GetTime()) <= 0
end

-------------------------------------------------------
-- Core helpers
-------------------------------------------------------
local function GetPlayerManaFrac()
    local mana = UnitMana("player")
    local maxMana = UnitManaMax("player")
    if not maxMana or maxMana <= 0 then return 0 end
    return mana / maxMana
end

local function GetDesiredAuraName()
    if currentMode == MODES.HEALER and IsSpellKnown(CONCENTRATION_AURA_NAME) then
        return CONCENTRATION_AURA_NAME
    end
    return AURA_NAME
end

local function HasDesiredAura()
    return HasBuffByName("player", GetDesiredAuraName())
end

local function GetDesiredBlessingName()
    if currentMode == MODES.HEALER then
        return BLESSING_BY_KEY[assignedBlessing] or BLESSING_WISDOM_NAME
    elseif currentMode == MODES.SUPPORT then
        return BLESSING_WISDOM_NAME
    end
    return BLESSING_MIGHT_NAME
end

local function HasDesiredBlessing()
    return HasBuffByName("player", GetDesiredBlessingName())
end

local function IsCommandLearned()
    return IsSpellKnown(SEAL_OF_COMMAND_NAME)
end

local function GetRetSealName()
    if IsCommandLearned() then
        return SEAL_OF_COMMAND_NAME
    end
    return SEAL_NAME
end

local function HasActiveRetSeal()
    return HasBuffByName("player", SEAL_OF_COMMAND_NAME) or HasBuffByName("player", SEAL_NAME)
end

local function GetHealerSealName()
    local manaFrac = GetPlayerManaFrac()
    local wantsWisdom = manaFrac < 0.6
    if wantsWisdom and IsSpellKnown(SEAL_OF_WISDOM_NAME) then
        return SEAL_OF_WISDOM_NAME
    end
    if IsSpellKnown(SEAL_OF_LIGHT_NAME) then
        return SEAL_OF_LIGHT_NAME
    end
    return SEAL_NAME
end

local function HasJudgementDebuff(unit)
    return HasDebuffByName(unit, JUDGEMENT_DEBUFF_NAME)
end

local function HasHammerStun(unit)
    return HasDebuffByName(unit, HAMMER_DEBUFF_NAME)
end

-------------------------------------------------------
-- Multi-enemy detection via hit frequency
-------------------------------------------------------
local hitEvents = {}
local HIT_WINDOW = 3
local HITS_FOR_HOJ = 4

local function TrackHitEvent()
    table.insert(hitEvents, GetTime())
end

local function GetRecentHitCount()
    local now = GetTime()
    local count = 0
    local newEvents = {}
    for _, t in ipairs(hitEvents) do
        if now - t <= HIT_WINDOW then
            count = count + 1
            table.insert(newEvents, t)
        end
    end
    hitEvents = newEvents
    return count
end

local combatTracker = CreateFrame("Frame")
combatTracker:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
combatTracker:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
combatTracker:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
combatTracker:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_MISSES")
combatTracker:SetScript("OnEvent", function()
    TrackHitEvent()
end)

-------------------------------------------------------
-- Utility: start auto attack WITHOUT toggling it off
-------------------------------------------------------
local function StartAutoAttack()
    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then return end
    if ATTACK_ACTION_SLOT and ATTACK_ACTION_SLOT > 0 then
        if not IsCurrentAction(ATTACK_ACTION_SLOT) then
            UseAction(ATTACK_ACTION_SLOT)
        end
    else
        AttackTarget()
    end
end

local function CastSpellOnUnit(spellName, unit)
    CastSpellByName(spellName)
    if SpellIsTargeting() then
        if UnitExists(unit) then
            SpellTargetUnit(unit)
        else
            SpellStopTargeting()
        end
    end
end

-------------------------------------------------------
-- Group scan helpers for healing
-------------------------------------------------------
local function ForEachGroupUnit(callback)
    if UnitExists("target") and UnitIsFriend("player", "target") then
        callback("target")
    end

    callback("player")

    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            callback("raid" .. i)
        end
    else
        for i = 1, GetNumPartyMembers() do
            callback("party" .. i)
        end
    end
end

local function GetLowestHealthUnit()
    local lowestUnit = nil
    local lowestFrac = 1
    ForEachGroupUnit(function(unit)
        if UnitExists(unit) and UnitCanAssist("player", unit) and not UnitIsDead(unit) then
            local maxHealth = UnitHealthMax(unit)
            if maxHealth and maxHealth > 0 then
                local frac = UnitHealth(unit) / maxHealth
                if frac < lowestFrac then
                    lowestFrac = frac
                    lowestUnit = unit
                end
            end
        end
    end)
    return lowestUnit, lowestFrac
end

-------------------------------------------------------
-- Mode: Ret/Support (offensive)
-------------------------------------------------------
local function HandleRetAndSupport()
    if UnitAffectingCombat("player") then
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if maxHealth > 0 and (health / maxHealth) < 0.20 then
            CastSpellByName(DIVINE_PROTECTION_NAME)
            return
        end
    end

    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        TargetNearestEnemy()
    end
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then return end

    if not HasDesiredAura() then
        CastSpellByName(GetDesiredAuraName())
        return
    end

    if not HasDesiredBlessing() then
        CastSpellByName(GetDesiredBlessingName())
        return
    end

    local recentHits = GetRecentHitCount()
    if recentHits >= HITS_FOR_HOJ and not HasHammerStun("target") then
        CastSpellByName(HAMMER_NAME)
        return
    end

    if IsSpellReady(JUDGEMENT_NAME) and not HasJudgementDebuff("target") and HasActiveRetSeal() then
        CastSpellByName(JUDGEMENT_NAME)
        return
    end

    if not HasActiveRetSeal() then
        CastSpellByName(GetRetSealName())
        return
    end

    StartAutoAttack()
end

-------------------------------------------------------
-- Mode: Healer (Holy)
-------------------------------------------------------
local function HandleHealerMode()
    if UnitAffectingCombat("player") then
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if maxHealth > 0 and (health / maxHealth) < 0.20 then
            CastSpellByName(DIVINE_PROTECTION_NAME)
            return
        end
    end

    if not HasDesiredAura() then
        CastSpellByName(GetDesiredAuraName())
        return
    end

    if not HasDesiredBlessing() then
        CastSpellByName(GetDesiredBlessingName())
        return
    end

    local healerSeal = GetHealerSealName()
    if healerSeal and not HasBuffByName("player", healerSeal) then
        CastSpellByName(healerSeal)
        return
    end

    local unit, frac = GetLowestHealthUnit()
    if not unit or not frac or frac >= 0.95 then
        return
    end

    if frac < 0.25 and IsSpellKnown(HOLY_SHOCK_NAME) and IsSpellReady(HOLY_SHOCK_NAME) then
        CastSpellOnUnit(HOLY_SHOCK_NAME, unit)
        return
    end

    if frac < 0.45 and IsSpellKnown(HOLY_LIGHT_NAME) then
        CastSpellOnUnit(HOLY_LIGHT_NAME, unit)
        return
    end

    if frac < 0.85 and IsSpellKnown(FLASH_OF_LIGHT_NAME) then
        CastSpellOnUnit(FLASH_OF_LIGHT_NAME, unit)
        return
    end
end

-------------------------------------------------------
-- Entry point
-------------------------------------------------------
function SmartSealAttack()
    if currentMode == MODES.HEALER then
        HandleHealerMode()
    else
        HandleRetAndSupport()
    end
end

-------------------------------------------------------
-- Slash command: /ssa
-------------------------------------------------------
local function TrimLower(msg)
    msg = msg or ""
    msg = tostring(msg)
    msg = string.lower(msg)
    msg = string.gsub(msg, "^%s+", "")
    msg = string.gsub(msg, "%s+$", "")
    return msg
end

local function SetMode(newMode)
    if currentMode == newMode then return end
    currentMode = newMode
    DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Mode set to " .. newMode)
end

SLASH_SMARTSEALATTACK1 = "/ssa"
SlashCmdList["SMARTSEALATTACK"] = function(msg)
    local m = TrimLower(msg)
    if m == "support on" or m == "support" then
        SetMode(MODES.SUPPORT)
        return
    elseif m == "support off" or m == "ret" then
        SetMode(MODES.RET)
        return
    elseif m == "healer on" or m == "healer" then
        SetMode(MODES.HEALER)
        return
    elseif m == "healer off" then
        SetMode(MODES.RET)
        return
    end

    local modeArg = string.match(m, "^mode%s+(%w+)$")
    if modeArg then
        if modeArg == "ret" or modeArg == MODES.RET then
            SetMode(MODES.RET)
            return
        elseif modeArg == "support" then
            SetMode(MODES.SUPPORT)
            return
        elseif modeArg == "healer" then
            SetMode(MODES.HEALER)
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Unknown mode " .. modeArg)
        return
    end

    local assignArg = string.match(m, "^assign%s+(%w+)$")
    if assignArg then
        if BLESSING_BY_KEY[assignArg] then
            assignedBlessing = assignArg
            DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Healer blessing assignment set to " .. BLESSING_BY_KEY[assignArg])
        else
            DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Unknown blessing assignment. Use wisdom/might/salvation/kings.")
        end
        return
    end

    SmartSealAttack()
end
