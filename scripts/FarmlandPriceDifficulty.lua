--[[
    FS25 Farmland Price Difficulty

    Adjusts farmland purchase prices according to the economic difficulty
    selected for the savegame. The mod uses its own farmland-specific
    multiplier table instead of EconomyManager.COST_MULTIPLIER.

    Default multipliers:
        EASY   = 0.75  (-25% compared with the reference price)
        NORMAL = 1.00  (reference / standard map-game price)
        HARD   = 1.25  (+25% compared with the reference price)

    Precision Farming compatibility
    -------------------------------
    Precision Farming can multiply Farmland:updatePrice() by the farmland's
    yieldPotential value. Because of the order in which Precision Farming
    initializes and later refreshes that value, the same farmland can otherwise
    receive a different purchase price after Farmland:updatePrice() is called
    again (for example after changing economic difficulty).

    To keep farmland prices stable, this mod deliberately removes the
    yieldPotential factor from the price calculated by Precision Farming before
    applying its own difficulty multiplier. Precision Farming remains active;
    only its yieldPotential-based farmland PRICE adjustment is neutralized.

    The final formula is therefore:

        final farmland price = reference farmland price * difficulty multiplier

    where the reference price is the standard price calculated by the game/map
    with the Precision Farming yieldPotential price factor removed when present.

    Debugging
    ---------
    Detailed per-farmland logging is disabled by default.

    Console command:
        fpdToggleDebug

    Calling the command toggles detailed diagnostic output in log.txt.
]]

local MOD_NAME = g_currentModName or "FS25_FarmlandPriceDifficulty"

FarmlandPriceDifficulty = {}
FarmlandPriceDifficulty.initialized = false
FarmlandPriceDifficulty.debug = false

-- -------------------------------------------------------------------------
-- Configuration
-- -------------------------------------------------------------------------

-- FS25 economic difficulty indices:
--   1 = Easy
--   2 = Normal
--   3 = Hard
--
-- These values affect farmland purchase prices only. They do not replace or
-- modify EconomyManager.COST_MULTIPLIER, so all other economy systems keep
-- using the game's normal economic-difficulty rules.
FarmlandPriceDifficulty.PRICE_MULTIPLIERS = {
    [1] = 0.75,
    [2] = 1.00,
    [3] = 1.25
}

FarmlandPriceDifficulty.DIFFICULTY_NAMES = {
    [1] = "EASY",
    [2] = "NORMAL",
    [3] = "HARD"
}

-- Keep this enabled for stable prices when Precision Farming is active.
--
-- If set to false, Precision Farming's yieldPotential multiplier becomes part
-- of the reference price. In that mode, the displayed farmland price can vary
-- when Precision Farming recalculates yieldPotential and updatePrice() runs.
FarmlandPriceDifficulty.IGNORE_PF_YIELD_POTENTIAL_FOR_PRICE = true

-- -------------------------------------------------------------------------
-- Helpers
-- -------------------------------------------------------------------------

--- Returns the farmland price multiplier configured for the current economic
--- difficulty and the difficulty index itself.
---
--- NORMAL (2) is used as a safe fallback while the mission information is not
--- yet available. The mod is initialized after the career has loaded, so this
--- fallback normally matters only as a defensive safeguard.
---
--- @return number multiplier Farmland-specific difficulty multiplier.
--- @return number difficulty FS25 economic difficulty index.
function FarmlandPriceDifficulty:getCurrentMultiplier()
    local difficulty = 2

    if g_currentMission ~= nil
        and g_currentMission.missionInfo ~= nil
        and g_currentMission.missionInfo.economicDifficulty ~= nil then
        difficulty = g_currentMission.missionInfo.economicDifficulty
    end

    return self.PRICE_MULTIPLIERS[difficulty] or 1.0, difficulty
end

--- Returns whether the official Precision Farming mod is currently loaded.
---
--- The explicit mod-name check is intentional: yieldPotential is a Precision
--- Farming field and should only be removed from the purchase-price calculation
--- when that mod is actually active.
---
--- @return boolean True when FS25_precisionFarming is loaded.
function FarmlandPriceDifficulty:isPrecisionFarmingActive()
    return g_modIsLoaded ~= nil
        and g_modIsLoaded["FS25_precisionFarming"] == true
end

-- -------------------------------------------------------------------------
-- Farmland price calculation
-- -------------------------------------------------------------------------

--- Overwrites Farmland:updatePrice().
---
--- Processing order:
---   1. Call superFunc(self), allowing the base game, map and already-installed
---      compatible overwrites (including Precision Farming) to calculate the
---      current farmland price normally.
---   2. If Precision Farming is active and a valid yieldPotential factor is
---      present, divide that factor back out. This recovers the stable
---      reference price used by this mod.
---   3. Apply exactly one farmland-difficulty multiplier.
---
--- Because superFunc() recalculates the price from its normal source every
--- time, repeated calls to farmland:updatePrice() do NOT compound our 0.75 /
--- 1.00 / 1.25 multiplier.
---
--- @param function superFunc Previous Farmland.updatePrice implementation.
function FarmlandPriceDifficulty:updatePrice(superFunc)
    -- First let the normal update chain calculate the farmland price.
    superFunc(self)

    local calculatedPrice = self.price
    if calculatedPrice == nil then
        return
    end

    local referencePrice = calculatedPrice
    local pfFactorRemoved = false

    -- Precision Farming applies:
    --     price = price * yieldPotential
    --
    -- Remove only that land-price factor so the difficulty system always uses
    -- the same reference price regardless of when PF last refreshed its data.
    if FarmlandPriceDifficulty.IGNORE_PF_YIELD_POTENTIAL_FOR_PRICE
        and FarmlandPriceDifficulty:isPrecisionFarmingActive()
        and self.yieldPotential ~= nil
        and self.yieldPotential > 0 then
        referencePrice = calculatedPrice / self.yieldPotential
        pfFactorRemoved = true
    end

    local multiplier, difficulty = FarmlandPriceDifficulty:getCurrentMultiplier()

    -- Apply our farmland-specific difficulty multiplier exactly once.
    self.price = referencePrice * multiplier

    -- Detailed diagnostics are intentionally available only on demand. They
    -- are useful for checking a specific farmland and for verifying the PF
    -- factor removal without filling log.txt during normal gameplay.
    if FarmlandPriceDifficulty.debug then
        local area = self.totalFieldArea or self.areaInHa
        local calculatedPerHa = nil
        local referencePerHa = nil
        local adjustedPerHa = nil

        if area ~= nil and area > 0 then
            calculatedPerHa = calculatedPrice / area
            referencePerHa = referencePrice / area
            adjustedPerHa = self.price / area
        end

        Logging.info(
            "[%s] Farmland %s | %s x%.2f | price %.2f -> ref %.2f -> final %.2f | area=%s | perHa %s -> %s -> %s | yieldPotential=%s | pfRemoved=%s",
            MOD_NAME,
            tostring(self.id),
            FarmlandPriceDifficulty.DIFFICULTY_NAMES[difficulty] or tostring(difficulty),
            multiplier,
            calculatedPrice,
            referencePrice,
            self.price,
            area ~= nil and string.format("%.4f", area) or "nil",
            calculatedPerHa ~= nil and string.format("%.2f", calculatedPerHa) or "nil",
            referencePerHa ~= nil and string.format("%.2f", referencePerHa) or "nil",
            adjustedPerHa ~= nil and string.format("%.2f", adjustedPerHa) or "nil",
            self.yieldPotential ~= nil and string.format("%.4f", self.yieldPotential) or "nil",
            pfFactorRemoved and "yes" or "no"
        )
    end
end

--- Forces all currently loaded farmlands to recalculate their purchase price.
---
--- This is required after changing economic difficulty because the difficulty
--- itself does not automatically change the already-cached farmland.price
--- values. Calling updatePrice() is safe because our overwrite starts each
--- calculation from superFunc() and therefore does not stack multipliers.
---
--- @return number count Number of farmland entries refreshed.
function FarmlandPriceDifficulty:updateFarmlands()
    if not self.initialized then
        return 0
    end

    if g_farmlandManager == nil or g_farmlandManager.farmlands == nil then
        return 0
    end

    local count = 0

    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland ~= nil and farmland.updatePrice ~= nil then
            farmland:updatePrice()
            count = count + 1
        end
    end

    return count
end

-- -------------------------------------------------------------------------
-- Debug console command
-- -------------------------------------------------------------------------

--- Toggles detailed per-farmland diagnostic logging.
---
--- Console command:
---     fpdToggleDebug
---
--- Debug mode is never saved and always starts disabled on the next game run.
function FarmlandPriceDifficulty.consoleCommandToggleDebug()
    FarmlandPriceDifficulty.debug = not FarmlandPriceDifficulty.debug

    local state = FarmlandPriceDifficulty.debug and "ON" or "OFF"
    Logging.info("[%s] Debug: %s", MOD_NAME, state)

    return string.format("%s debug: %s", MOD_NAME, state)
end

-- -------------------------------------------------------------------------
-- Initialization and game hooks
-- -------------------------------------------------------------------------

--- Installs the Farmland:updatePrice() overwrite and the debug console command.
---
--- Initialization is deliberately performed from Mission00.loadMission00Finished
--- rather than BaseMission.loadMapFinished. At this stage the career/savegame
--- is loaded and Precision Farming has already installed its own price overwrite,
--- allowing this mod to become the outer layer of the calculation chain.
function FarmlandPriceDifficulty:init()
    if self.initialized then
        return
    end

    Farmland.updatePrice = Utils.overwrittenFunction(
        Farmland.updatePrice,
        FarmlandPriceDifficulty.updatePrice
    )

    self.initialized = true

    addConsoleCommand(
        "fpdToggleDebug",
        "Toggle detailed Farmland Price Difficulty logging",
        "consoleCommandToggleDebug",
        FarmlandPriceDifficulty
    )

    -- Recalculate once after installing the overwrite so all already-loaded
    -- farmlands immediately receive the correct price for the saved difficulty.
    local updatedCount = self:updateFarmlands()
    local multiplier, difficulty = self:getCurrentMultiplier()

    -- Keep normal log output intentionally compact: one initialization line.
    Logging.info(
        "[%s] Loaded: %s x%.2f, %d farmlands refreshed.",
        MOD_NAME,
        self.DIFFICULTY_NAMES[difficulty] or tostring(difficulty),
        multiplier,
        updatedCount
    )
end

--- Initialize after the complete career/savegame has finished loading.
Mission00.loadMission00Finished = Utils.appendedFunction(
    Mission00.loadMission00Finished,
    function(...)
        FarmlandPriceDifficulty:init()
    end
)

--- Recalculate all farmland prices immediately after the player changes the
--- economic difficulty in the savegame settings.
FSBaseMission.setEconomicDifficulty = Utils.appendedFunction(
    FSBaseMission.setEconomicDifficulty,
    function(...)
        if FarmlandPriceDifficulty.initialized then
            local updatedCount = FarmlandPriceDifficulty:updateFarmlands()
            local multiplier, difficulty = FarmlandPriceDifficulty:getCurrentMultiplier()

            -- One short line per actual difficulty change; detailed values are
            -- available through fpdToggleDebug when needed.
            Logging.info(
                "[%s] Difficulty: %s x%.2f, %d farmlands refreshed.",
                MOD_NAME,
                FarmlandPriceDifficulty.DIFFICULTY_NAMES[difficulty] or tostring(difficulty),
                multiplier,
                updatedCount
            )
        end
    end
)
