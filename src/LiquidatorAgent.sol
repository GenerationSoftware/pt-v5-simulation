pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment } from "src/Environment.sol";

contract LiquidatorAgent {

    Environment public env;

    constructor (Environment _env) {
        env = _env;
        env.prizeToken().approve(address(env.router()), type(uint).max);
    }

    function check(uint exchangeRatePrizeTokenToUnderlyingFixedPoint18) public {
        uint gasCostInPrizeTokens = env.gasConfig().gasPriceInPrizeTokens * env.gasConfig().gasUsagePerLiquidation;

        uint availableVaultShares = env.pair().maxAmountOut();
        uint requiredPrizeTokens = env.pair().computeExactAmountIn(availableVaultShares);

        uint liquidationCost = requiredPrizeTokens;
        uint liquidationRevenue = (availableVaultShares * exchangeRatePrizeTokenToUnderlyingFixedPoint18) / 1e18;

        // console2.log("liquidationCost\t", liquidationCost);
        // console2.log("liquidationRevenue\t", liquidationRevenue);

        if (liquidationRevenue > liquidationCost) {
            uint profit = liquidationRevenue - liquidationCost;
            if (profit > gasCostInPrizeTokens) {
                console2.log("LIQUIDATING ", block.timestamp);
                env.prizeToken().mint(address(this), requiredPrizeTokens);
                env.router().swapExactAmountOut(
                    env.pair(),
                    address(this),
                    availableVaultShares,
                    type(uint).max
                );
            }
        }

    }

}