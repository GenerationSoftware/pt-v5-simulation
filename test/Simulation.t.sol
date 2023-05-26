// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { UFixed32x4 } from "v5-liquidator/libraries/FixedMathLib.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";

import {
    Environment,
    PrizePoolConfig,
    LiquidatorConfig,
    ClaimerConfig,
    GasConfig
} from "src/Environment.sol";

import { ClaimerAgent } from "src/ClaimerAgent.sol";
import { DrawAgent } from "src/DrawAgent.sol";
import { LiquidatorAgent } from "src/LiquidatorAgent.sol";

contract SimulationTest is Test {

    function testSimulation() public {

        uint32 drawPeriodSeconds = 1 hours;

        PrizePoolConfig memory prizePoolConfig = PrizePoolConfig({
            grandPrizePeriodDraws: 10,
            drawPeriodSeconds: drawPeriodSeconds,
            nextDrawStartsAt: uint64(block.timestamp) + drawPeriodSeconds,
            numberOfTiers: 2,
            tierShares: 100,
            canaryShares: 10,
            reserveShares: 10,
            claimExpansionThreshold: UD2x18.wrap(0.8e18),
            smoothing: SD1x18.wrap(0.9e18)
        });

        LiquidatorConfig memory liquidatorConfig = LiquidatorConfig({
            swapMultiplier: UFixed32x4.wrap(0.3e4),
            liquidityFraction: UFixed32x4.wrap(0.02e4),
            virtualReserveIn: 1e18,
            virtualReserveOut: 1e18,
            mink: 1e18*1e18
        });

        ClaimerConfig memory claimerConfig = ClaimerConfig({
            minimumFee: 0.0001e18,
            maximumFee: 1000e18,
            timeToReachMaxFee: drawPeriodSeconds,
            maxFeePortionOfPrize: UD2x18.wrap(0.5e18)
        });

        GasConfig memory gasConfig = GasConfig({
            gasPriceInPrizeTokens: 10 gwei,
            gasUsagePerClaim: 150_000,
            gasUsagePerLiquidation: 500_000,
            gasUsagePerCompleteDraw: 200_000
        });

        Environment env = new Environment(
            prizePoolConfig,
            liquidatorConfig,
            claimerConfig,
            gasConfig
        );

        uint duration = 10 days;
        uint timeStep = 5 minutes;
        uint startTime = block.timestamp;

        uint totalValueLocked = 1_000_000e18;
        uint numUsers = 100;

        uint exchangeRatePrizeTokenToUnderlyingFixedPoint18 = 1e18;

        env.addUsers(numUsers, totalValueLocked / numUsers);

        ClaimerAgent claimerAgent = new ClaimerAgent(env);
        LiquidatorAgent liquidatorAgent = new LiquidatorAgent(env);
        DrawAgent drawAgent = new DrawAgent(env);

        env.setPrizePoolManager(address(drawAgent));
        env.setApr(0.04e18);

        for (uint i = startTime; i < duration; i += timeStep) {
            vm.warp(i);
            claimerAgent.check();
            liquidatorAgent.check(exchangeRatePrizeTokenToUnderlyingFixedPoint18);
            drawAgent.check();
        }

    }

}
