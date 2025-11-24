---@diagnostic disable: undefined-global
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
local JUDGEMENT_OF_COMMAND_DEBUFF_NAME = "Judgement of Command"
local JUDGEMENT_OF_LIGHT_DEBUFF_NAME  = "Judgement of Light"
local JUDGEMENT_OF_WISDOM_DEBUFF_NAME = "Judgement of Wisdom"
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
local HEALER_DPS_MODE = false
local healerJudgeSeal = nil
local supportHealTarget = nil
local HEAL_PULSE_ACTIVE = false

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

-- Next action display
local nextActionText = "Ready"
local function SetNextAction(text)
    nextActionText = text
    if SSA_NextActionFrame and SSA_NextActionFrame.text then
        SSA_NextActionFrame.text:SetText("SSA: " .. text)
    end
end

local function EnsureNextActionFrame()
    if SSA_NextActionFrame then return end
    local f = CreateFrame("Frame", "SSA_NextActionFrame", UIParent)
    f:SetWidth(190)
    f:SetHeight(24)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    f:SetBackdropColor(0, 0, 0, 0.4)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetAllPoints(f)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    text:SetText("SSA: Ready")
    f.text = text
end

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

local function IsJudgementReadyOn(unit)
    if not IsSpellKnown(JUDGEMENT_NAME) or not IsSpellReady(JUDGEMENT_NAME) then
        return false
    end
    if not unit or not UnitExists(unit) or UnitIsDead(unit) then
        return false
    end
    -- Judgement is 10 yards; use interact distance 3 (10-yard check) when available.
    if CheckInteractDistance and not CheckInteractDistance(unit, 3) then
        return false
    end
    return true
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

local function GetUnitHealthFrac(unit)
    local maxHealth = UnitHealthMax(unit)
    if not maxHealth or maxHealth <= 0 then return nil end
    return UnitHealth(unit) / maxHealth
end

local function GetDesiredAuraName()
    if currentMode == MODES.HEALER and IsSpellKnown(CONCENTRATION_AURA_NAME) then
        return CONCENTRATION_AURA_NAME
    end
    return AURA_NAME
end

local function GetDesiredBlessingName()
    if currentMode == MODES.HEALER then
        return BLESSING_BY_KEY[assignedBlessing] or BLESSING_WISDOM_NAME
    elseif currentMode == MODES.SUPPORT then
        return BLESSING_WISDOM_NAME
    end
    return BLESSING_MIGHT_NAME
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

local function HasRetJudgementDebuff(unit)
    return HasDebuffByName(unit, JUDGEMENT_OF_COMMAND_DEBUFF_NAME) or HasDebuffByName(unit, JUDGEMENT_DEBUFF_NAME)
end

local function HasHealerJudgementDebuff(unit)
    return HasDebuffByName(unit, JUDGEMENT_OF_LIGHT_DEBUFF_NAME) or HasDebuffByName(unit, JUDGEMENT_OF_WISDOM_DEBUFF_NAME)
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
    if not UnitExists(unit) then return end

    local hadTarget = UnitExists("target")

    -- Force correct unit into cursor/target, then restore.
    TargetUnit(unit)
    CastSpellByName(spellName)
    if SpellIsTargeting() then
        SpellTargetUnit(unit)
        if SpellIsTargeting() then
            SpellStopTargeting()
        end
    end

    if hadTarget then
        TargetLastTarget()
    else
        ClearTarget()
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
    if UnitExists("pet") then
        callback("pet")
    end

    if GetNumRaidMembers() and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            callback("raid" .. i)
            if UnitExists("raidpet" .. i) then
                callback("raidpet" .. i)
            end
        end
    else
        for i = 1, GetNumPartyMembers() do
            callback("party" .. i)
            if UnitExists("partypet" .. i) then
                callback("partypet" .. i)
            end
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

-- Return first melee/ranged physical dps that should have Blessing of Might.
local MIGHT_FAVORING_CLASSES = {
    WARRIOR = true,
    ROGUE = true,
    HUNTER = true,
}

local function NeedsBlessingOfMight(unit)
    if not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAssist("player", unit) then
        return false
    end
    local _, class = UnitClass(unit)
    if not class or not MIGHT_FAVORING_CLASSES[class] then
        return false
    end
    return not HasBuffByName(unit, BLESSING_MIGHT_NAME)
end

local function FindMightTargetNeedingBuff()
    local target = nil
    ForEachGroupUnit(function(unit)
        if not target and NeedsBlessingOfMight(unit) then
            target = unit
        end
    end)
    return target
end

-------------------------------------------------------
-- Mode: Retribution / Support (shared)
-------------------------------------------------------
local function HandleRetAndSupport()
    SetNextAction("Ret/Support: evaluating")
    if UnitAffectingCombat("player") then
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if maxHealth > 0 and (health / maxHealth) < 0.20 then
            SetNextAction("Divine Protection")
            CastSpellByName(DIVINE_PROTECTION_NAME)
            return
        end
    end

    local auraName = GetDesiredAuraName()
    if IsSpellKnown(auraName) and not HasBuffByName("player", auraName) then
        SetNextAction("Aura: " .. auraName)
        CastSpellByName(auraName)
        return
    end

    if not HEAL_PULSE_ACTIVE then
        local blessName = GetDesiredBlessingName()
        if IsSpellKnown(blessName) and not HasBuffByName("player", blessName) then
            SetNextAction("Blessing: " .. blessName)
            CastSpellOnUnit(blessName, "player")
            return
        end
    end

    -- Keep Blessing of Might on physical DPS (warriors/rogues/hunters)
    if not HEAL_PULSE_ACTIVE and IsSpellKnown(BLESSING_MIGHT_NAME) then
        local mightTarget = FindMightTargetNeedingBuff()
        if mightTarget then
            SetNextAction("BoM -> " .. (UnitName(mightTarget) or mightTarget))
            CastSpellOnUnit(BLESSING_MIGHT_NAME, mightTarget)
            return
        end
    end

    -- Support mode: Flash of Light allies below 50% until they are above 85%
    if currentMode == MODES.SUPPORT and IsSpellKnown(FLASH_OF_LIGHT_NAME) then
        local lowestUnit, lowestFrac = GetLowestHealthUnit()

        -- Continue healing an in-progress target until safe
        if supportHealTarget then
            local frac = GetUnitHealthFrac(supportHealTarget)
            if not frac or frac >= 0.85 or not UnitCanAssist("player", supportHealTarget) or UnitIsDead(supportHealTarget) then
                supportHealTarget = nil
            else
                SetNextAction("FoL -> " .. (UnitName(supportHealTarget) or supportHealTarget))
                CastSpellOnUnit(FLASH_OF_LIGHT_NAME, supportHealTarget)
                return
            end
        end

        -- Start healing a new low target
        if lowestUnit and lowestFrac and lowestFrac < 0.50 then
            supportHealTarget = lowestUnit
            SetNextAction("FoL -> " .. (UnitName(lowestUnit) or lowestUnit))
            CastSpellOnUnit(FLASH_OF_LIGHT_NAME, lowestUnit)
            return
        end
    end

    -- Offensive target acquisition (after support heal so healing works without an enemy target)
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        SetNextAction("Targeting enemy")
        TargetNearestEnemy()
    end
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        SetNextAction("No valid target")
        return
    end

    local recentHits = GetRecentHitCount()
    if recentHits >= HITS_FOR_HOJ and not HasHammerStun("target") and IsSpellKnown(HAMMER_NAME) then
        SetNextAction("Hammer of Justice")
        CastSpellByName(HAMMER_NAME)
        return
    end

    if IsJudgementReadyOn("target") and not HasRetJudgementDebuff("target") and HasActiveRetSeal() then
        SetNextAction("Judgement")
        CastSpellByName(JUDGEMENT_NAME)
        return
    end

    local retSeal = GetRetSealName()
    if IsSpellKnown(retSeal) and not HasActiveRetSeal() then
        SetNextAction("Seal: " .. retSeal)
        CastSpellByName(retSeal)
        return
    end

    SetNextAction("Auto-attack")
    StartAutoAttack()
end

-------------------------------------------------------
-- Mode: Healer (Holy)
-------------------------------------------------------
local function HandleHealerMode()
    SetNextAction("Healer: evaluating")
    if UnitAffectingCombat("player") then
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if maxHealth > 0 and (health / maxHealth) < 0.20 then
            SetNextAction("Divine Protection")
            CastSpellByName(DIVINE_PROTECTION_NAME)
            return
        end
    end

    local auraName = GetDesiredAuraName()
    if IsSpellKnown(auraName) and not HasBuffByName("player", auraName) then
        SetNextAction("Aura: " .. auraName)
        CastSpellByName(auraName)
        return
    end

    local blessName = GetDesiredBlessingName()
    if IsSpellKnown(blessName) and not HasBuffByName("player", blessName) then
        SetNextAction("Blessing: " .. blessName)
        CastSpellOnUnit(blessName, "player")
        return
    end

    local unit, frac = GetLowestHealthUnit()
    if not frac then frac = 1 end

    local shouldDps = HEALER_DPS_MODE and frac >= 0.90

    -- Skip seals entirely in pure healing mode to save mana.
    -- Only manage seals when healer DPS mode is enabled.
    if HEALER_DPS_MODE and not shouldDps then
        local healerSeal = GetHealerSealName()
        if healerSeal and not HasBuffByName("player", healerSeal) then
            SetNextAction("Seal: " .. healerSeal)
            CastSpellByName(healerSeal)
            return
        end
    end

    if unit and frac < 0.25 and IsSpellKnown(HOLY_SHOCK_NAME) and IsSpellReady(HOLY_SHOCK_NAME) then
        SetNextAction("Holy Shock -> " .. (UnitName(unit) or unit))
        CastSpellOnUnit(HOLY_SHOCK_NAME, unit)
        return
    end

    if unit and frac < 0.45 and IsSpellKnown(HOLY_LIGHT_NAME) then
        SetNextAction("Holy Light -> " .. (UnitName(unit) or unit))
        CastSpellOnUnit(HOLY_LIGHT_NAME, unit)
        return
    end

    if unit and frac < 0.85 and IsSpellKnown(FLASH_OF_LIGHT_NAME) then
        SetNextAction("Flash of Light -> " .. (UnitName(unit) or unit))
        CastSpellOnUnit(FLASH_OF_LIGHT_NAME, unit)
        return
    end

    -- Keep Blessing of Might on physical DPS (warriors/rogues/hunters) when the group is stable
    if IsSpellKnown(BLESSING_MIGHT_NAME) then
        local mightTarget = FindMightTargetNeedingBuff()
        if mightTarget then
            SetNextAction("BoM -> " .. (UnitName(mightTarget) or mightTarget))
            CastSpellOnUnit(BLESSING_MIGHT_NAME, mightTarget)
            return
        end
    end

    -- Optional DPS while healing: only if group stable and mana high enough
    if shouldDps then
        if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
            SetNextAction("Targeting enemy")
            TargetNearestEnemy()
        end
        if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
            SetNextAction("No valid target")
            return
        end

        local manaFrac = GetPlayerManaFrac()

        -- Seed healerJudgeSeal from current buffs or defaults
        if not healerJudgeSeal then
            if HasBuffByName("player", SEAL_OF_WISDOM_NAME) then
                healerJudgeSeal = SEAL_OF_WISDOM_NAME
            elseif HasBuffByName("player", SEAL_OF_LIGHT_NAME) then
                healerJudgeSeal = SEAL_OF_LIGHT_NAME
            elseif manaFrac < 0.70 and IsSpellKnown(SEAL_OF_WISDOM_NAME) then
                healerJudgeSeal = SEAL_OF_WISDOM_NAME
            elseif IsSpellKnown(SEAL_OF_LIGHT_NAME) then
                healerJudgeSeal = SEAL_OF_LIGHT_NAME
            elseif IsSpellKnown(SEAL_OF_WISDOM_NAME) then
                healerJudgeSeal = SEAL_OF_WISDOM_NAME
            end
        end

        -- Hysteresis: drop to Wisdom when low, back to Light when comfortably high
        if healerJudgeSeal == SEAL_OF_LIGHT_NAME and manaFrac < 0.65 and IsSpellKnown(SEAL_OF_WISDOM_NAME) then
            healerJudgeSeal = SEAL_OF_WISDOM_NAME
        elseif healerJudgeSeal == SEAL_OF_WISDOM_NAME and manaFrac > 0.80 and IsSpellKnown(SEAL_OF_LIGHT_NAME) then
            healerJudgeSeal = SEAL_OF_LIGHT_NAME
        end

        -- If swapping seals, judge the current one first (if ready and no healer judgement up)
        local currentSeal = nil
        if HasBuffByName("player", SEAL_OF_WISDOM_NAME) then
            currentSeal = SEAL_OF_WISDOM_NAME
        elseif HasBuffByName("player", SEAL_OF_LIGHT_NAME) then
            currentSeal = SEAL_OF_LIGHT_NAME
        end

        if currentSeal and healerJudgeSeal and currentSeal ~= healerJudgeSeal then
            if IsJudgementReadyOn("target") and not HasHealerJudgementDebuff("target") then
                CastSpellByName(JUDGEMENT_NAME)
                return
            end
        end

        local judgeSeal = healerJudgeSeal

        if judgeSeal then
            if not HasBuffByName("player", judgeSeal) then
                SetNextAction("Seal: " .. judgeSeal)
                CastSpellByName(judgeSeal)
                return
            end

            if IsJudgementReadyOn("target") and not HasHealerJudgementDebuff("target") then
                SetNextAction("Judgement")
                CastSpellByName(JUDGEMENT_NAME)
                return
            end

            -- Reapply seal after judging (consumed)
            if not HasBuffByName("player", judgeSeal) then
                SetNextAction("Seal: " .. judgeSeal)
                CastSpellByName(judgeSeal)
                return
            end
        end

        SetNextAction("Auto-attack")
        StartAutoAttack()
        return
    end

    SetNextAction("Healer: idle")
end

-------------------------------------------------------
-- Entry point
-------------------------------------------------------
local function SmartSealHealPulse()
    -- Temporarily run healer logic without flipping currentMode persistently.
    local prevMode = currentMode
    local prevHealerDps = HEALER_DPS_MODE
    currentMode = MODES.HEALER
    HEALER_DPS_MODE = false -- keep this as a pure heal pulse
    HEAL_PULSE_ACTIVE = true
    HandleHealerMode()
    HEAL_PULSE_ACTIVE = false
    HEALER_DPS_MODE = prevHealerDps
    currentMode = prevMode
end

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
local function SetMode(newMode)
    if currentMode == newMode then return end
    currentMode = newMode
    if newMode ~= MODES.HEALER then
        HEALER_DPS_MODE = false
        healerJudgeSeal = nil
    end
    SetNextAction("Mode: " .. newMode)
    DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Mode set to " .. newMode)
end

SLASH_SMARTSEALATTACK1 = "/ssa"
SlashCmdList["SMARTSEALATTACK"] = function(msg)
    local m = msg or ""
    m = tostring(m)
    m = string.lower(m)
    m = string.gsub(m, "^%s+", "")
    m = string.gsub(m, "%s+$", "")
    if m == "healer" or m == "mode healer" then
        SetMode(MODES.HEALER)
        return
    elseif m == "ret" or m == "mode ret" or m == "dps" then
        SetMode(MODES.RET)
        return
    elseif m == "support" or m == "mode support" then
        SetMode(MODES.SUPPORT)
        return
    elseif m == "healer dps on" then
        HEALER_DPS_MODE = true
        DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Healer DPS mode ON (only with >90% group hp and >65% mana)")
        return
    elseif m == "healer dps off" then
        HEALER_DPS_MODE = false
        DEFAULT_CHAT_FRAME:AddMessage("SmartSealAttack: Healer DPS mode OFF")
        return
    elseif m == "heal" or m == "heal pulse" or m == "heal now" then
        SmartSealHealPulse()
        return
    end

    local _, _, assignArg = string.find(m, "^assign%s+(%w+)$")
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

-------------------------------------------------------
-- Basic load message
-------------------------------------------------------
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_LOGIN")
loadFrame:SetScript("OnEvent", function()
    EnsureNextActionFrame()
    SetNextAction("Ready")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00SmartSealAttack loaded.|r Type |cffffff00/ssa|r.")
end)
