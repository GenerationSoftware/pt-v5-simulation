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

    function check(SD59x18 underlyingTokensPerPrizeToken) public {
        uint gasCostInPrizeTokens = env.gasConfig().gasPriceInPrizeTokens * env.gasConfig().gasUsagePerLiquidation;
        uint maxAmountOut = env.pair().maxAmountOut();

        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ checking maxAmountOut", maxAmountOut / 1e18);
        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ period", env.pair().getAuction().period);
        // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ elapsed", env.pair().getElapsedTime());

        uint bestAmountOut;
        uint bestAmountIn;
        uint profit;

        uint iterations = 10;
        for (uint i = 1; i <= iterations; i++) {
            uint amountOut = (i * maxAmountOut) / iterations;
            uint amountIn = env.pair().computeExactAmountIn(amountOut);

            // console2.log("amountIn for amountOut", amountIn, amountOut);

            uint amountOutInPrizeTokens = uint(convert(convert(int(amountOut)).div(underlyingTokensPerPrizeToken)));
            if (amountOutInPrizeTokens > amountIn) {
                uint thisProfit = amountOutInPrizeTokens - amountIn;
                if (thisProfit > gasCostInPrizeTokens && thisProfit > profit) {
                    bestAmountOut = amountOut;
                    bestAmountIn = amountIn;
                    profit = thisProfit;
                }
            }
        }


        if (profit > 0) {
            env.prizeToken().mint(address(this), bestAmountIn);
            env.router().swapExactAmountOut(
                env.pair(),
                address(this),
                bestAmountOut,
                type(uint).max
            );

            totalApproxProfit += profit;

            SD59x18 amountOutInPrizeTokens = convert(int(bestAmountOut)).div(underlyingTokensPerPrizeToken);
            SD59x18 efficiency = convert(int(bestAmountIn)).div(amountOutInPrizeTokens);
            uint efficiencyPercent = uint(convert(efficiency.mul(convert(100))));

            // console2.log("@ ", block.timestamp / 1 days);
            LiquidationPair.Auction memory auction = env.pair().getAuction();
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LiquidatorAgent swapped POOL for Yield; efficiency", bestAmountIn / 1e18, bestAmountOut / 1e18, efficiencyPercent);
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tRemaining", env.pair().maxAmountOut() / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tGas cost", gasCostInPrizeTokens / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Period, time", auction.period, block.timestamp);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ underlyingTokensPerPrizeToken", underlyingTokensPerPrizeToken);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ price average", env.pair().priceAverage().unwrap() / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Accrued / claimed", uint(auction.amountAccrued) / 1e18, uint(auction.amountClaimed) / 1e18);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tcurrent time", block.timestamp);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tauction time", env.pair().getPeriodStart());
            uint timeSinceAuctionStarted = block.timestamp - env.pair().getPeriodStart();
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \t\tTime since auction started", timeSinceAuctionStarted);
            // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Elapsed since draw awarded", block.timestamp - env.prizePool().lastCompletedDrawAwardedAt());
            // console2.log("New reserve: ", env.pair().virtualReserveIn()/1e18, env.pair().virtualReserveOut()/1e18);
            // uint availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
            // console2.log("Available yield", availableYield, "/1e18:", availableYield / 1e18);
        }
    }

}
