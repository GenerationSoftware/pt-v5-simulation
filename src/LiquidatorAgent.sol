pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment } from "src/Environment.sol";

contract LiquidatorAgent {

    Environment public env;
    uint totalApproxProfit;

    constructor (Environment _env) {
        env = _env;
        env.prizeToken().approve(address(env.router()), type(uint).max);
    }

    function check(uint exchangeRatePrizeTokenToUnderlyingFixedPoint18) public {
        uint gasCostInPrizeTokens = env.gasConfig().gasPriceInPrizeTokens * env.gasConfig().gasUsagePerLiquidation;

        // console2.log("~~~~ gasCostInPrizeTokens\t", gasCostInPrizeTokens);

        uint availableVaultShares = env.pair().maxAmountOut();
        uint requiredPrizeTokens = env.pair().computeExactAmountIn(availableVaultShares);

        // console2.log("<<<< availableVaultShares\t", availableVaultShares);
        // console2.log("\t requiredPrizeTokens\t", requiredPrizeTokens);

        uint iterations = 10;
        uint max = (iterations**iterations);

        uint want;
        uint profit;

        // if(block.timestamp == 1703394000 || block.timestamp == 1703397600 || block.timestamp == 1703401200 || block.timestamp == 1703404800) {
        //     console2.log("Available yield", availableVaultShares / 1e18, "Required Prize Tokens:", requiredPrizeTokens / 1e18);
        //     console2.log("Current reserve: ", env.pair().virtualReserveIn(), env.pair().virtualReserveOut());
        // }

        for (uint i = 1; i <= iterations; i++) {
            uint thisWant = (i**i * availableVaultShares) / max;

            uint requiredPrizeTokens = env.pair().computeExactAmountIn(thisWant);

            uint liquidationCost = requiredPrizeTokens;
            uint liquidationRevenue = (thisWant * 1e18) / exchangeRatePrizeTokenToUnderlyingFixedPoint18;

            if (liquidationRevenue > liquidationCost) {
                uint thisProfit = liquidationRevenue - liquidationCost;
                if (thisProfit > gasCostInPrizeTokens && thisProfit > profit) {
                    if(block.timestamp == 1703401200 || block.timestamp == 1703404800) {
                        // console2.log("New Want:", thisWant, "New Profit:", thisProfit);
                    }
                    want = thisWant;
                    profit = thisProfit;
                }
            }
        }

        if (profit > 0) {
            // console2.log("~~~~ profit: ", liquidationRevenue > liquidationCost);
            uint requiredPrizeTokens = env.pair().computeExactAmountIn(want);
            // console2.log("~~~~ want\t\t\t", want);
            // console2.log("~~~~ requiredPrizeTokens\t", requiredPrizeTokens);
            // console2.log("~~~~ liquidationCost\t", liquidationCost);
            // console2.log("~~~~ liquidationRevenue\t", liquidationRevenue);

            // console2.log("LIQUIDATING ", block.timestamp);
            env.prizeToken().mint(address(this), requiredPrizeTokens);
            uint cost = env.router().swapExactAmountOut(
                env.pair(),
                address(this),
                want,
                type(uint).max
            );

            totalApproxProfit += profit;

            // console2.log("@ ", block.timestamp / 1 days);
            console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LiquidatorAgent swapped POOL for Yield", cost/1e18, want/1e18);
            // console2.log("New reserve: ", env.pair().virtualReserveIn()/1e18, env.pair().virtualReserveOut()/1e18);
            uint availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
            // console2.log("Available yield", availableYield, "/1e18:", availableYield / 1e18);
        }
    }

}