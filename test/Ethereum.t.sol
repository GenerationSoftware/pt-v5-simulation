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

    uint32 drawPeriodSeconds = 14 days;

    uint duration = 300 days;
    uint timeStep = 1 hours;
    uint startTime = block.timestamp;

    uint totalValueLocked = 500_000e18;
    uint apr = 0.04e18;
    uint numUsers = 2;

    uint exchangeRatePrizeTokenToUnderlyingFixedPoint18 = 1e18;

    PrizePoolConfig public prizePoolConfig;
    LiquidatorConfig public liquidatorConfig;
    ClaimerConfig public claimerConfig;
    GasConfig public gasConfig;
    Environment public env;

    ClaimerAgent public claimerAgent;
    LiquidatorAgent public liquidatorAgent;
    DrawAgent public drawAgent;

    function setUp() public {
        prizePoolConfig = PrizePoolConfig({
            grandPrizePeriodDraws: 10,
            drawPeriodSeconds: drawPeriodSeconds,
            nextDrawStartsAt: uint64(block.timestamp),
            numberOfTiers: 2,
            tierShares: 100,
            canaryShares: 50,
            reserveShares: 200,
            claimExpansionThreshold: UD2x18.wrap(0.8e18),
            smoothing: SD1x18.wrap(0.9e18)
        });

        liquidatorConfig = LiquidatorConfig({
            swapMultiplier: UFixed32x4.wrap(0.3e4),
            liquidityFraction: UFixed32x4.wrap(0.1e4),
            virtualReserveIn: 1000e18,
            virtualReserveOut: 1000e18,
            mink: 1000e18*1000e18
        });

        claimerConfig = ClaimerConfig({
            minimumFee: 0.0001e18,
            maximumFee: 1000e18,
            timeToReachMaxFee: drawPeriodSeconds/2,
            maxFeePortionOfPrize: UD2x18.wrap(0.5e18)
        });

        // gas price is currently 50 gwei of ether.
        // ether is worth 1800 POOL
        // 50 * 1800 = 90000 POOL
        gasConfig = GasConfig({
            gasPriceInPrizeTokens: 90000 gwei,
            gasUsagePerClaim: 150_000,
            gasUsagePerLiquidation: 500_000,
            gasUsagePerCompleteDraw: 200_000
        });

        env = new Environment(
            prizePoolConfig,
            liquidatorConfig,
            claimerConfig,
            gasConfig
        );

        claimerAgent = new ClaimerAgent(env);
        liquidatorAgent = new LiquidatorAgent(env);
        drawAgent = new DrawAgent(env);
    }

    function testSimulation() public {
        env.addUsers(numUsers, totalValueLocked / numUsers);

        env.setPrizePoolManager(address(drawAgent));
        env.setApr(apr);

        for (uint i = startTime; i < duration; i += timeStep) {
            vm.warp(i);
            env.mintYield();
            // claimerAgent.check();
            liquidatorAgent.check(exchangeRatePrizeTokenToUnderlyingFixedPoint18);
            drawAgent.check();
        }

        uint totalDraws = duration / drawPeriodSeconds;
        uint missedDraws = (totalDraws) - drawAgent.drawCount();
        console2.log("Expected draws", totalDraws);
        console2.log("Actual draws", drawAgent.drawCount());

        console2.log("Missed Draws", missedDraws);

    }

}
