// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

import { ClaimerAgent } from "../../src/agent/Claimer.sol";
import { DrawAgent } from "../../src/agent/Draw.sol";
import { LiquidatorAgent } from "../../src/agent/Liquidator.sol";

import {
  OptimismEnvironment,
  CgdaLiquidatorConfig,
  DaLiquidatorConfig,
  ClaimerConfig,
  RngAuctionConfig
} from "../../src/environment/Optimism.sol";

import { Constant } from "../../src/utils/Constant.sol";
import { SD59x18OverTime } from "../../src/SD59x18OverTime.sol";

import { BaseTest } from "./Base.t.sol";

contract OptimismTest is BaseTest {
  string simulatorCsv;

  uint256 duration;
  uint256 timeStep = 20 minutes;
  uint256 startTime;

  uint256 totalValueLocked;
  uint256 apr = 0.025e18; // 2.5%
  uint256 numUsers = 1;

  SD59x18OverTime public exchangeRateOverTime; // Prize Token to Underlying Token

  PrizePoolConfig public prizePoolConfig;
  ClaimerConfig public claimerConfig;
  RngAuctionConfig public rngAuctionConfig;
  OptimismEnvironment public env;

  ClaimerAgent public claimerAgent;
  LiquidatorAgent public liquidatorAgent;

  uint256 verbosity;

  function setUp() public {
    startTime = block.timestamp + 10000 days;
    vm.warp(startTime);

    totalValueLocked = vm.envUint("TVL") * 1e18;
    console2.log("TVL: ", vm.envUint("TVL"));

    if (totalValueLocked == 0) {
      revert("Please define TVL env var > 0");
    }

    verbosity = vm.envUint("VERBOSITY");
    console2.log("VERBOSITY: ", verbosity);

    duration = vm.envUint("DURATION");
    console2.log("DURATION: ", duration);

    initOutputFileCsv();

    setUpExchangeRate();
    // setUpExchangeRateFromJson();

    // setUpApr(startTime);
    setUpAprFromJson(startTime);

    console2.log("Setting up at timestamp: ", block.timestamp, "day:", block.timestamp / 1 days);
    console2.log("Draw Period (sec): ", DRAW_PERIOD_SECONDS);

    prizePoolConfig = PrizePoolConfig({
      drawPeriodSeconds: DRAW_PERIOD_SECONDS,
      grandPrizePeriodDraws: GRAND_PRIZE_PERIOD_DRAWS,
      firstDrawOpensAt: uint48(startTime + DRAW_PERIOD_SECONDS),
      numberOfTiers: MIN_NUMBER_OF_TIERS,
      reserveShares: RESERVE_SHARES,
      tierShares: TIER_SHARES,
      smoothing: _getContributionsSmoothing()
    });

    claimerConfig = ClaimerConfig({
      minimumFee: CLAIMER_MIN_FEE,
      maximumFee: CLAIMER_MAX_FEE,
      timeToReachMaxFee: _getClaimerTimeToReachMaxFee(),
      maxFeePortionOfPrize: _getClaimerMaxFeePortionOfPrize()
    });

    rngAuctionConfig = RngAuctionConfig({
      sequenceOffset: _getRngAuctionSequenceOffset(prizePoolConfig.firstDrawOpensAt),
      auctionDuration: AUCTION_DURATION,
      auctionTargetTime: AUCTION_TARGET_TIME,
      firstAuctionTargetRewardFraction: FIRST_AUCTION_TARGET_REWARD_FRACTION
    });

    env = new OptimismEnvironment();
    env.initialize(prizePoolConfig, claimerConfig, rngAuctionConfig);

    ///////////////// Liquidator /////////////////
    // Initialize one of the liquidators. Comment the other out.

    env.initializeCgdaLiquidator(
      CgdaLiquidatorConfig({
        decayConstant: _getDecayConstant(),
        exchangeRatePrizeTokenToUnderlying: exchangeRateOverTime.get(startTime),
        periodLength: DRAW_PERIOD_SECONDS,
        periodOffset: uint32(startTime),
        targetFirstSaleTime: _getTargetFirstSaleTime()
      })
    );

    //////////////////////////////////////////////

    claimerAgent = new ClaimerAgent(env, vm, verbosity);
    liquidatorAgent = new LiquidatorAgent(env, vm);
  }

  // NOTE: Order matters for ABI decode.
  struct HistoricPrice {
    uint256 exchangeRate;
    uint256 timestamp;
  }

  function setUpExchangeRateFromJson() public {
    exchangeRateOverTime = new SD59x18OverTime();

    string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicPrices.json");
    string memory jsonData = vm.readFile(jsonFile);
    // NOTE: Options for exchange rate are: .usd or .eth
    bytes memory usdData = vm.parseJson(jsonData, "$.usd");
    HistoricPrice[] memory prices = abi.decode(usdData, (HistoricPrice[]));

    uint256 initialTimestamp = prices[0].timestamp;
    for (uint256 i = 0; i < prices.length; i++) {
      HistoricPrice memory priceData = prices[i];
      uint256 timeElapsed = priceData.timestamp - initialTimestamp;

      exchangeRateOverTime.add(
        startTime + timeElapsed,
        SD59x18.wrap(int256(priceData.exchangeRate * 1e9))
      );
    }
  }

  function setUpExchangeRate() public {
    exchangeRateOverTime = new SD59x18OverTime();
    // Realistic test case
    // POOL/UNDERLYING = 0.000001
    // exchangeRateOverTime.add(startTime, wrap(1e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 2), wrap(1.5e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 4), wrap(2e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 6), wrap(4e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 8), wrap(3e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 10), wrap(1e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 12), wrap(5e17));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 14), wrap(1e17));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 16), wrap(5e16));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 18), wrap(1e16));

    // Custom test case
    exchangeRateOverTime.add(startTime, wrap(1e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 1), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 2), wrap(1.05e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 3), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 4), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 5), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 6), wrap(1.12e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 7), wrap(1.5e18));
  }

  function testOptimism() public noGasMetering recordEvents {
    env.addUsers(numUsers, totalValueLocked / numUsers);

    env.setApr(aprOverTime.get(startTime));

    initOutputFileCsv();

    for (uint256 i = startTime; i < startTime + duration; i += timeStep) {
      vm.warp(i);
      vm.roll(block.number + 1);

      // Cache data at beginning of tick
      uint256 availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
      uint256 availableVaultShares = env.pair().maxAmountOut();
      uint256 prizePoolReserve = env.prizePool().reserve();
      uint256 requiredPrizeTokens = availableVaultShares != 0
        ? env.pair().computeExactAmountIn(availableVaultShares)
        : 0;

      // uint256 unrealizedReserve = env.prizePool().reserveForNextDraw();
      // string memory valuesPart1 = string.concat(
      //   vm.toString(i),
      //   ",",
      //   vm.toString((i - startTime) / DRAW_PERIOD_SECONDS),
      //   ",",
      //   vm.toString(availableYield),
      //   ",",
      //   vm.toString(availableYield / 1e18),
      //   ",",
      //   vm.toString(availableVaultShares),
      //   ",",
      //   vm.toString(availableVaultShares / 1e18),
      //   ",",
      //   vm.toString(requiredPrizeTokens),
      //   ",",
      //   vm.toString(requiredPrizeTokens / 1e18),
      //   ","
      // );
      //
      // // split to avoid stack too deep
      // string memory valuesPart2 = string.concat(
      //   vm.toString(prizePoolReserve),
      //   ",",
      //   vm.toString(prizePoolReserve / 1e18)
      // );
      //
      // vm.writeLine(runStatsOut, string.concat(valuesPart1, valuesPart2));

      // Let agents do their thing
      env.setApr(aprOverTime.get(i));
      env.mintYield();
      claimerAgent.check();
      liquidatorAgent.check(exchangeRateOverTime.get(block.timestamp));

      // Log data
      logToCsv(
        SimulatorLog({
          drawId: env.prizePool().getLastAwardedDrawId(),
          timestamp: block.timestamp,
          availableYield: availableYield,
          availableVaultShares: availableVaultShares,
          requiredPrizeTokens: requiredPrizeTokens,
          prizePoolReserve: prizePoolReserve,
          apr: aprOverTime.get(i),
          tvl: totalValueLocked
        })
      );
    }

    printMissedPrizes();
    printTotalNormalPrizes();
    printTotalCanaryPrizes();
    printTotalClaimFees();
    printPrizeSummary();
    printFinalPrizes();
  }

  function printMissedPrizes() public view {
    uint256 lastDrawId = env.prizePool().getLastAwardedDrawId();
    for (uint32 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint256 numTiers = claimerAgent.drawNumberOfTiers(drawId);
      for (uint8 tier = 0; tier < numTiers; tier++) {
        uint256 prizeCount = claimerAgent.drawNormalTierComputedPrizeCounts(drawId, tier);
        uint256 claimCount = claimerAgent.drawNormalTierClaimedPrizeCounts(drawId, tier);
        if (claimCount < prizeCount) {
          console2.log(
            "!!!!! MISSED PRIZES draw, tier, count",
            drawId,
            tier,
            prizeCount - claimCount
          );
        }
      }
    }
  }

  function printTotalNormalPrizes() public view {
    uint256 normalComputed = claimerAgent.totalNormalPrizesComputed();
    uint256 normalClaimed = claimerAgent.totalNormalPrizesClaimed();
    console2.log("");
    console2.log("Number of normal prizes", normalComputed);
    console2.log("Number of prizes claimed", normalClaimed);
    console2.log("Missed normal prizes", normalComputed - normalClaimed);
  }

  function printTotalCanaryPrizes() public view {
    uint256 canaryComputed = claimerAgent.totalCanaryPrizesComputed();
    uint256 canaryClaimed = claimerAgent.totalCanaryPrizesClaimed();
    console2.log("");
    console2.log("Number of canary prizes", canaryComputed);
    console2.log("Number of canary prizes claimed", canaryClaimed);
    console2.log("Missed canary prizes", canaryComputed - canaryClaimed);
  }

  function printTotalClaimFees() public view {
    uint256 totalPrizes = claimerAgent.totalNormalPrizesClaimed() +
      claimerAgent.totalCanaryPrizesClaimed();
    uint256 averageFeePerClaim = totalPrizes > 0 ? claimerAgent.totalFees() / totalPrizes : 0;
    console2.log("");
    console2.log("Average fee per claim (cents): ", averageFeePerClaim / 1e16);
  }

  function printPrizeSummary() public view {
    uint8 maxTiers;
    uint256 lastDrawId = env.prizePool().getLastAwardedDrawId();
    for (uint32 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint8 numTiers = claimerAgent.drawNumberOfTiers(drawId);
      if (numTiers > maxTiers) {
        maxTiers = numTiers;
      }
    }

    uint256[] memory tierPrizeCounts = new uint256[](maxTiers);
    for (uint32 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint8 numTiers = claimerAgent.drawNumberOfTiers(drawId);
      if (numTiers > maxTiers) {
        maxTiers = numTiers;
      }
      for (uint8 tier = 0; tier < numTiers; tier++) {
        tierPrizeCounts[tier] += claimerAgent.drawNormalTierClaimedPrizeCounts(drawId, tier);
      }
    }

    for (uint8 tier = 0; tier < tierPrizeCounts.length; tier++) {
      console2.log("Tier", tier, "prizes", tierPrizeCounts[tier]);
    }
  }

  function printFinalPrizes() public view {
    uint8 numTiers = env.prizePool().numberOfTiers();
    for (uint8 tier = 0; tier < numTiers; tier++) {
      console2.log(
        "Final prize size for tier",
        tier,
        "is",
        env.prizePool().getTierPrizeSize(tier) / 1e18
      );
    }
  }

  ////////////////////////// CSV LOGGING //////////////////////////

  struct SimulatorLog {
    uint256 drawId;
    uint256 timestamp;
    uint256 availableYield;
    uint256 availableVaultShares;
    uint256 requiredPrizeTokens;
    uint256 prizePoolReserve;
    uint256 apr;
    uint256 tvl;
  }

  // Clears and logs the CSV headers to the file
  function initOutputFileCsv() public {
    simulatorCsv = string.concat(vm.projectRoot(), "/data/simulatorOut.csv");
    vm.writeFile(simulatorCsv, "");
    vm.writeLine(
      simulatorCsv,
      "Draw ID, Timestamp, Available Yield, Available Vault Shares, Required Prize Tokens, Prize Pool Reserve, APR, TVL"
    );
  }

  function logToCsv(SimulatorLog memory log) public {
    vm.writeLine(
      simulatorCsv,
      string.concat(
        vm.toString(log.drawId),
        ",",
        vm.toString(log.timestamp),
        ",",
        vm.toString(log.availableYield),
        ",",
        vm.toString(log.availableVaultShares),
        ",",
        vm.toString(log.requiredPrizeTokens),
        ",",
        vm.toString(log.prizePoolReserve),
        ",",
        vm.toString(log.apr),
        ",",
        vm.toString(log.tvl)
      )
    );
  }

  /////////////////////////////////////////////////////////////////
}
