// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { Vault } from "pt-v5-vault/Vault.sol";

import { ClaimerAgent } from "../../src/agent/Claimer.sol";
import { DrawAgent } from "../../src/agent/Draw.sol";
import { LiquidatorAgent } from "../../src/agent/Liquidator.sol";

import { OptimismEnvironment } from "../../src/environment/Optimism.sol";

import { BaseTest } from "./Base.t.sol";

contract OptimismTest is BaseTest {
  string simulatorCsvFile = string.concat(vm.projectRoot(), "/data/optimismSimulatorOut.csv");
  string simulatorCsvColumns =
    "Draw ID, Timestamp, Available Yield, Available Vault Shares, Required Prize Tokens, Prize Pool Reserve, Pending Reserve Contributions, APR, TVL";

  uint256 duration;
  uint256 startTime;
  uint48 firstDrawOpensAt;

  uint256 totalValueLocked;

  PrizePoolConfig public prizePoolConfig;
  ClaimerConfig public claimerConfig;
  RngAuctionConfig public rngAuctionConfig;
  OptimismEnvironment public env;

  ILiquidationPair public pair;
  PrizePool public prizePool;
  Vault public vault;

  ClaimerAgent public claimerAgent;
  DrawAgent public drawAgent;
  LiquidatorAgent public liquidatorAgent;

  uint256 verbosity;

  function setUp() public {
    startTime = block.timestamp + 10000 days;
    vm.warp(startTime);

    firstDrawOpensAt = _getFirstDrawOpensAt(startTime);

    totalValueLocked = vm.envUint("TVL") * 1e18;
    console2.log("TVL: ", vm.envUint("TVL"));

    if (totalValueLocked == 0) {
      revert("Please define TVL env var > 0");
    }

    verbosity = vm.envUint("VERBOSITY");
    console2.log("VERBOSITY: ", verbosity);

    // We offset by 2 draw periods cause the first draw opens 1 draw period after start time
    // and one draw period need to pass before we can award it
    duration = vm.envUint("DRAWS") * DRAW_PERIOD_SECONDS + DRAW_PERIOD_SECONDS * 2;
    console2.log("DURATION: ", duration);
    console2.log("DURATION IN DAYS: ", duration / 1 days);

    initOutputFileCsv(simulatorCsvFile, simulatorCsvColumns);

    setUpExchangeRate(startTime);
    // setUpExchangeRateFromJson(startTime);

    setUpApr(startTime);
    // setUpAprFromJson(startTime);

    console2.log("Setting up at timestamp: ", block.timestamp, "day:", block.timestamp / 1 days);
    console2.log("Draw Period (sec): ", DRAW_PERIOD_SECONDS);

    prizePoolConfig = PrizePoolConfig({
      drawPeriodSeconds: DRAW_PERIOD_SECONDS,
      grandPrizePeriodDraws: GRAND_PRIZE_PERIOD_DRAWS,
      firstDrawOpensAt: firstDrawOpensAt,
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
      sequenceOffset: _getRngAuctionSequenceOffset(firstDrawOpensAt),
      auctionDuration: AUCTION_DURATION,
      auctionTargetTime: AUCTION_TARGET_TIME,
      firstAuctionTargetRewardFraction: FIRST_AUCTION_TARGET_REWARD_FRACTION
    });

    env = new OptimismEnvironment(prizePoolConfig, claimerConfig, rngAuctionConfig);
    env.initializeCgdaLiquidator(
      CgdaLiquidatorConfig({
        decayConstant: _getDecayConstant(),
        exchangeRatePrizeTokenToUnderlying: exchangeRateOverTime.get(startTime),
        periodLength: DRAW_PERIOD_SECONDS,
        periodOffset: uint32(startTime),
        targetFirstSaleTime: _getTargetFirstSaleTime()
      })
    );

    pair = env.pair();
    prizePool = env.prizePool();
    vault = env.vault();

    claimerAgent = new ClaimerAgent(env, verbosity);
    drawAgent = new DrawAgent(env);
    liquidatorAgent = new LiquidatorAgent(env);
  }

  function testOptimism() public noGasMetering recordEvents {
    uint256 previousDrawAuctionSequenceId;

    env.addUsers(NUM_USERS, totalValueLocked / NUM_USERS);
    env.setApr(aprOverTime.get(startTime));

    for (uint256 i = startTime; i <= startTime + duration; i += TIME_STEP) {
      vm.warp(i);
      vm.roll(block.number + 1);

      // Cache data at beginning of tick
      uint256 availableYield = vault.liquidatableBalanceOf(address(vault));
      uint256 availableVaultShares = pair.maxAmountOut();
      uint256 prizePoolReserve = prizePool.reserve();
      uint256 requiredPrizeTokens = availableVaultShares != 0
        ? pair.computeExactAmountIn(availableVaultShares)
        : 0;

      uint256 pendingReserveContributions = prizePool.pendingReserveContributions();

      // Let agents do their thing
      env.setApr(aprOverTime.get(i));
      env.mintYield();

      liquidatorAgent.check(exchangeRateOverTime.get(block.timestamp));
      previousDrawAuctionSequenceId = drawAgent.check(previousDrawAuctionSequenceId);
      claimerAgent.check();

      uint256[] memory logs = new uint256[](9);
      logs[0] = prizePool.getLastAwardedDrawId();
      logs[1] = block.timestamp;
      logs[2] = availableYield;
      logs[3] = availableVaultShares;
      logs[4] = requiredPrizeTokens;
      logs[5] = prizePoolReserve;
      logs[6] = pendingReserveContributions;
      logs[7] = aprOverTime.get(i);
      logs[8] = totalValueLocked;

      logUint256ToCsv(simulatorCsvFile, logs);
    }

    env.removeUsers();

    printDraws();
    printMissedPrizes();
    printTotalNormalPrizes();
    printTotalCanaryPrizes();
    printTotalClaimFees();
    printPrizeSummary();
    printFinalPrizes();
    printLiquidity();
  }

  function printMissedPrizes() public view {
    uint256 lastDrawId = prizePool.getLastAwardedDrawId();
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

  function printLiquidity() public view {
    uint reserve = env.prizePool().reserve() + env.prizePool().pendingReserveContributions();
    uint totalLiquidity = env.prizePool().getTotalContributedBetween(1, env.prizePool().getOpenDrawId());
    console2.log("");
    console2.log("Total liquidity: ", totalLiquidity / 1e18);
    console2.log("Final prize liquidity", (env.prizePool().accountedBalance() - reserve) / 1e18);
    console2.log("Final reserve liquidity", (reserve) / 1e18);
  }

  function printDraws() public view {
    uint256 totalDraws = (block.timestamp - (firstDrawOpensAt + DRAW_PERIOD_SECONDS)) /
      DRAW_PERIOD_SECONDS;
    uint256 missedDraws = (totalDraws) - drawAgent.drawCount();
    console2.log("");
    console2.log("Expected draws", totalDraws);
    console2.log("Actual draws", drawAgent.drawCount());
    console2.log("Missed Draws", missedDraws);
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
    console2.log("");
    uint8 maxTiers;
    uint256 lastDrawId = prizePool.getLastAwardedDrawId();
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
    console2.log("");
    uint8 numTiers = prizePool.numberOfTiers();
    console2.log("Final number of tiers: %s", numTiers);
    for (uint8 tier = 0; tier < numTiers; tier++) {
      console2.log(
        "Final prize size for tier",
        tier,
        "is",
        prizePool.getTierPrizeSize(tier) / 1e18
      );
    }
  }
}
