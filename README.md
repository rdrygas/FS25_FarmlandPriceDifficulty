# FS25 Farmland Price Difficulty

**Farmland Price Difficulty** is a script mod for **Farming Simulator 25** that makes farmland purchase prices respond to the savegame's economic difficulty.

The base game uses the same farmland price regardless of the economic difficulty. This mod adds a dedicated multiplier table for land prices without changing `EconomyManager.COST_MULTIPLIER`, so the rest of the game's economy continues to use the standard FS25 rules.

## Assumptions and goals

The mod was designed around the following assumptions:

- **Normal** should preserve the standard map/game farmland price.
- **Easy** should make land moderately cheaper rather than dramatically reducing the price.
- **Hard** should make land genuinely more expensive than the standard price.
- Farmland difficulty should be independent from the multipliers FS25 uses for other economic costs.
- Changing economic difficulty while playing should update farmland prices immediately.
- With **Precision Farming**, farmland prices should remain stable and should not change merely because `Farmland:updatePrice()` was called again.

The default balance is intentionally symmetrical around Normal:

| Economic difficulty | Multiplier | Difference from Normal |
|---|---:|---:|
| Easy | `0.75` | -25% |
| Normal | `1.00` | unchanged |
| Hard | `1.25` | +25% |

## How it works

The mod overwrites `Farmland:updatePrice()` rather than changing the global `EconomyManager.COST_MULTIPLIER` table.

Every time a farmland price is recalculated, the mod:

1. lets the base game, the map and already-installed compatible price hooks calculate the farmland price normally;
2. if Precision Farming is active, removes its `yieldPotential` factor from the **land purchase price**;
3. treats the recovered value as the reference price;
4. applies the farmland-specific difficulty multiplier exactly once.

The effective formula is:

```text
final farmland price = reference farmland price × difficulty multiplier
```

Because `superFunc()` recalculates the original price before the multiplier is applied, repeated price refreshes do not compound the multiplier.

### Example

If a farmland costs **$83,433/ha** at the standard map/game price:

| Economic difficulty | Calculation | Result |
|---|---:|---:|
| Easy | 83,433 × 0.75 | ~62,575 / ha |
| Normal | 83,433 × 1.00 | ~83,433 / ha |
| Hard | 83,433 × 1.25 | ~104,291 / ha |

## Precision Farming compatibility

Precision Farming can multiply `Farmland:updatePrice()` by the farmland's `yieldPotential` value. Its initialization order means that the displayed land price can otherwise depend on **when** `updatePrice()` is called.

For example, during testing on Riverbend Springs, farmland 24 had:

```text
yieldPotential = 0.9665
standard price = ~83,433 / ha
PF-adjusted recalculated price = ~80,638 / ha
```

Without compensation, changing the economic difficulty could therefore make the same HARD price alternate between approximately **104,291/ha** and **100,798/ha**.

To avoid this, the mod removes the Precision Farming `yieldPotential` factor from the farmland purchase price before applying its own difficulty multiplier. Precision Farming itself remains active; only its `yieldPotential`-based **land price adjustment** is neutralized.

This behavior is controlled by:

```lua
FarmlandPriceDifficulty.IGNORE_PF_YIELD_POTENTIAL_FOR_PRICE = true
```

Keeping it set to `true` is recommended.

## Automatic price refresh

Farmland prices are recalculated:

- once after the career/savegame has finished loading;
- immediately after changing the economic difficulty in the game settings.

Initialization is deliberately hooked to `Mission00.loadMission00Finished`, so the saved difficulty and Precision Farming hooks are already available before this mod installs its final price layer.

## Configuration

The default multipliers are near the top of `FarmlandPriceDifficulty.lua`:

```lua
FarmlandPriceDifficulty.PRICE_MULTIPLIERS = {
    [1] = 0.75, -- Easy
    [2] = 1.00, -- Normal
    [3] = 1.25  -- Hard
}
```

You can change only these three values to rebalance land prices. For example:

```lua
FarmlandPriceDifficulty.PRICE_MULTIPLIERS = {
    [1] = 0.80,
    [2] = 1.00,
    [3] = 1.40
}
```

This would make Easy 20% cheaper than Normal and Hard 40% more expensive.

The change affects farmland prices only. Other game costs continue to use the normal FS25 economy settings.

## Debugging

Detailed debug logging is **disabled by default**.

Use the following console command to toggle it:

```text
fpdToggleDebug
```

When enabled, `log.txt` includes one detailed line for every farmland showing, among other values:

- economic difficulty and multiplier;
- price calculated by the normal update chain;
- recovered reference price;
- final adjusted price;
- farmland area;
- calculated, reference and final price per hectare;
- Precision Farming `yieldPotential`;
- whether the Precision Farming price factor was removed.

Debug mode is not saved and starts disabled after every game restart.

## Normal log output

During normal gameplay the mod keeps logging intentionally short. Typical messages are:

```text
Info: [FS25_FarmlandPriceDifficulty] Loaded: NORMAL x1.00, 93 farmlands refreshed.
Info: [FS25_FarmlandPriceDifficulty] Difficulty: HARD x1.25, 93 farmlands refreshed.
```

## Scope and limitations

- Farming Simulator 25.
- Single-player use is the intended and tested scope; multiplayer support is disabled in `modDesc.xml`.
- The mod changes farmland **purchase prices only**.
- Precision Farming remains fully usable, but its `yieldPotential` factor is intentionally excluded from farmland purchase prices when the compatibility option is enabled.
- Another mod that overwrites farmland prices after this mod has initialized may still change the final result.

## Changelog

### 1.0.0.0

- Initial stable release.
- Added an independent farmland price multiplier table:
  - Easy: 0.75;
  - Normal: 1.00;
  - Hard: 1.25.
- Normal difficulty preserves the standard map/game reference price.
- Added automatic price refresh after career loading and after changing economic difficulty.
- Moved the price adjustment to `Farmland:updatePrice()` so the multiplier is applied to a complete farmland price calculation.
- Added Precision Farming compatibility by removing the `yieldPotential` factor from farmland purchase prices before applying the difficulty multiplier.
- Fixed farmland prices changing after repeated difficulty switches when Precision Farming was active.
- Added optional `fpdToggleDebug` diagnostics.
- Debug logging is disabled by default.
- Reduced normal `log.txt` output to concise initialization and difficulty-change messages.
