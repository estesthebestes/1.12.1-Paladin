-- SmartSealAttack.lua
-- Helper for Paladins: target nearest enemy, keep key buffs up,
-- maintain Judgement of Righteousness, handle emergencies, and auto-attack without toggling.

local SEAL_NAME              = "Seal of Righteousness"
local AURA_NAME              = "Devotion Aura"
local BLESSING_NAME          = "Blessing of Might"
local JUDGEMENT_NAME         = "Judgement"
local JUDGEMENT_DEBUFF_NAME  = "Judgement of Righteousness"
local HAMMER_NAME            = "Hammer of Justice"
local HAMMER_DEBUFF_NAME     = "Hammer of Justice"
local DIVINE_PROTECTION_NAME = "Divine Protection"

-- Put your "Attack" ability on this action slot (1 = bottom-left first button)
local ATTACK_ACTION_SLOT = 1

-------------------------------------------------------
-- Generic tooltip-based buff check
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

-------------------------------------------------------
-- Generic tooltip-based debuff check
-------------------------------------------------------
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
-- Specific helpers
-------------------------------------------------------
local function HasDevotionAura()
    return HasBuffByName("player", AURA_NAME)
end

local function HasBlessingOfMight()
    return HasBuffByName("player", BLESSING_NAME)
end

local function HasSealOfRighteousness()
    return HasBuffByName("player", SEAL_NAME)
end

local function HasJudgementDebuff(unit)
    return HasDebuffByName(unit, JUDGEMENT_DEBUFF_NAME)
end

local function HasHammerStun(unit)
    return HasDebuffByName(unit, HAMMER_DEBUFF_NAME)
end

-------------------------------------------------------
-- Judgement cooldown helper (spellbook index based)
-------------------------------------------------------
local judgementSpellIndex = nil

local function FindJudgementInSpellbook()
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        for i = 1, numSpells do
            local spellIndex = offset + i
            local name = GetSpellName(spellIndex, "spell")
            if name == JUDGEMENT_NAME then
                judgementSpellIndex = spellIndex
                return
            end
        end
    end
end

local function IsJudgementReady()
    if not judgementSpellIndex then
        FindJudgementInSpellbook()
    end
    if not judgementSpellIndex then return false end
    local start, duration, enabled = GetSpellCooldown(judgementSpellIndex, "spell")
    if not start or enabled == 0 then return false end
    if duration == 0 then return true end
    return (start + duration - GetTime()) <= 0
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
combatTracker:SetScript("OnEvent", function(_, event, msg)
    TrackHitEvent()
end)

-------------------------------------------------------
-- Start auto attack WITHOUT toggling it off
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

-------------------------------------------------------
-- Core function: SmartSealAttack
-------------------------------------------------------
function SmartSealAttack()
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

    if not HasDevotionAura() then
        CastSpellByName(AURA_NAME)
        return
    end

    if not HasBlessingOfMight() then
        CastSpellByName(BLESSING_NAME)
        return
    end

    local recentHits = GetRecentHitCount()
    if recentHits >= HITS_FOR_HOJ and not HasHammerStun("target") then
        CastSpellByName(HAMMER_NAME)
        return
    end

    if IsJudgementReady() and not HasJudgementDebuff("target") and HasSealOfRighteousness() then
        CastSpellByName(JUDGEMENT_NAME)
        return
    end

    if not HasSealOfRighteousness() then
        CastSpellByName(SEAL_NAME)
        return
    end

    StartAutoAttack()
end

-------------------------------------------------------
-- Slash command: /ssa
-------------------------------------------------------
SLASH_SMARTSEALATTACK1 = "/ssa"
SlashCmdList["SMARTSEALATTACK"] = function()
    SmartSealAttack()
end

-------------------------------------------------------
-- Basic load message
-------------------------------------------------------

