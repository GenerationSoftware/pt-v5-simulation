pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment } from "src/Environment.sol";
import { LiquidationPair } from "v5-cgda-liquidator/LiquidationPair.sol";
import { SD59x18, wrap, convert } from "prb-math/SD59x18.sol";

contract LiquidatorAgent {

    Environment public env;
    uint totalApproxProfit;

    constructor (Environment _env) {
        env = _env;
        env.prizeToken().approve(address(env.router()), type(uint).max);
    }

    function check(SD59x18 exchangeRatePrizeTokenToUnderlying) public {
        uint gasCostInPrizeTokens = env.gasConfig().gasPriceInPrizeTokens * env.gasConfig().gasUsagePerLiquidation;
        uint maxAmountOut = env.pair().maxAmountOut();

        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ checking maxAmountOut", maxAmountOut / 1e18);
        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ period", env.pair().getAuction().period);
        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ elapsed", env.pair().getElapsedTime());

        uint amountOut = maxAmountOut;
        uint amountIn = env.pair().computeExactAmountIn(amountOut);
        uint profit;

        uint amountOutInPrizeTokens = uint(convert(convert(int(amountOut)).mul(exchangeRatePrizeTokenToUnderlying)));

        if (amountOutInPrizeTokens > amountIn) {
            profit = amountOutInPrizeTokens - amountIn;
        }

        if (profit > gasCostInPrizeTokens) {
            env.prizeToken().mint(address(this), amountIn);
            env.router().swapExactAmountOut(
                env.pair(),
                address(this),
                amountOut,
                type(uint).max
            );

            totalApproxProfit += profit;

            SD59x18 amountOutInPrizeTokens = convert(int(amountOut)).mul(exchangeRatePrizeTokenToUnderlying);
            SD59x18 efficiency = convert(int(amountIn)).div(amountOutInPrizeTokens);
            uint efficiencyPercent = uint(convert(efficiency.mul(convert(100))));

            uint elapsedSinceDrawEnded = block.timestamp - env.prizePool().lastClosedDrawEndedAt();
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ @ ", elapsedSinceDrawEnded);
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LiquidatorAgent swapped POOL for Yield; efficiency", amountIn, amountOut, efficiencyPercent);
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tRemaining yield", env.pair().maxAmountOut());
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tGas cost", gasCostInPrizeTokens / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Period, time", auction.period, block.timestamp);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ exchangeRatePrizeTokenToUnderlying", exchangeRatePrizeTokenToUnderlying);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ price average", env.pair().priceAverage().unwrap() / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Accrued / claimed", uint(auction.amountAccrued) / 1e18, uint(auction.amountClaimed) / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tcurrent time", block.timestamp);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tauction time", env.pair().getPeriodStart());
            // console2.log("New reserve: ", env.pair().virtualReserveIn()/1e18, env.pair().virtualReserveOut()/1e18);
            // uint availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
            // console2.log("Available yield", availableYield, "/1e18:", availableYield / 1e18);
        }
    }

}
