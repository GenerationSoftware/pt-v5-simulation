// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";

import { ClaimerAgent } from "../../src/agent/Claimer.sol";
import { DrawAgent } from "../../src/agent/Draw.sol";
import { LiquidatorAgent } from "../../src/agent/Liquidator.sol";

import { SingleChainEnvironment } from "../../src/environment/SingleChain.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { Config } from "../../src/utils/Config.sol";
import { Constant } from "../../src/utils/Constant.sol";
import { Utils } from "../../src/utils/Utils.sol";

import { UintOverTime } from "../utils/UintOverTime.sol";

contract SingleChainDeploymentTest is CommonBase, Config, Constant, StdCheats, Test, Utils {

  UintOverTime public aprOverTime;

  // NOTE: Order matters for ABI decode.
  struct HistoricApr {
    uint256 apr;
    uint256 timestamp;
  }

  string simulatorCsvFile = string.concat(vm.projectRoot(), "/data/singleChainSimulatorOut.csv");
  string simulatorCsvColumns =
    "Draw ID, Timestamp, Available Yield, Available Prize Vault Shares, Required Prize Tokens, Prize Pool Reserve, Pending Reserve Contributions, APR, TVL";

  uint256 duration;
  uint256 startTime;
  uint48 firstDrawOpensAt;

  uint256 totalValueLocked;

  PrizePoolConfig public prizePoolConfig;
  ClaimerConfig public claimerConfig;
  RngAuctionConfig public rngAuctionConfig;
  SingleChainEnvironment public env;
  GasConfig public gasConfig;

  ILiquidationPair public pair;
  PrizePool public prizePool;
  PrizeVault public vault;

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
      drawTimeout: 30 // 30 draws = 1 month
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

    gasConfig = GasConfig({
      gasPriceInPrizeTokens: 1.29 gwei,
      gasUsagePerStartDraw: 152_473,
      gasUsagePerRelayDraw: 405_000,
      gasUsagePerClaim: 150_000,
      gasUsagePerLiquidation: 500_000,
      rngCostInPrizeTokens: 0.0005e18
    });

    env = new SingleChainEnvironment(prizePoolConfig, claimerConfig, rngAuctionConfig, gasConfig);
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
      uint256 availablePrizeVaultShares = pair.maxAmountOut();
      uint256 prizePoolReserve = prizePool.reserve();
      uint256 requiredPrizeTokens = availablePrizeVaultShares != 0
        ? pair.computeExactAmountIn(availablePrizeVaultShares)
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
      logs[3] = availablePrizeVaultShares;
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
    uint finalPrizeLiquidity = env.prizePool().accountedBalance() - reserve;
    console2.log("");
    console2.log("Total liquidity: ", formatPrizeTokens(totalLiquidity));
    console2.log("Final prize liquidity", formatPrizeTokens(finalPrizeLiquidity));
    console2.log("Final reserve liquidity", formatPrizeTokens(reserve));
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
    console2.log("Average fee per claim (WETH): ", formatPrizeTokens(averageFeePerClaim));
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
        formatPrizeTokens(prizePool.getTierPrizeSize(tier))
      );
    }
  }

  function setUpApr(uint256 _startTime) public {
    aprOverTime = new UintOverTime();

    // Realistic test case
    aprOverTime.add(_startTime, Constant.SIMPLE_APR);
  }

  function setUpAprFromJson(uint256 _startTime) public {
    aprOverTime = new UintOverTime();

    string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicAaveApr.json");
    string memory jsonData = vm.readFile(jsonFile);

    // NOTE: Options for APR are: .usd or .eth
    bytes memory usdData = vm.parseJson(jsonData, "$.usd");
    HistoricApr[] memory aprData = abi.decode(usdData, (HistoricApr[]));

    uint256 initialTimestamp = aprData[0].timestamp;
    for (uint256 i = 0; i < aprData.length; i++) {
      HistoricApr memory rowData = aprData[i];
      aprOverTime.add(_startTime + (rowData.timestamp - initialTimestamp), rowData.apr);
    }
  }

  modifier recordEvents() {
    string memory filePath = string.concat(vm.projectRoot(), "/data/rawEventsOut.csv");
    vm.writeFile(filePath, "");
    vm.writeLine(filePath, "Event Number, Emitter, Data, Topic 0, Topic 1, Topic 2, Topic 3,");
    vm.recordLogs();

    _;

    Vm.Log[] memory entries = vm.getRecordedLogs();

    for (uint256 i = 0; i < entries.length; i++) {
      Vm.Log memory log = entries[i];

      string memory row;
      row = string.concat(
        vm.toString(i),
        ",",
        vm.toString(log.emitter),
        ",",
        vm.toString(log.data),
        ","
      );

      for (uint256 j = 0; j < log.topics.length; ++j) {
        row = string.concat(row, vm.toString(log.topics[j]), ",");
      }
      for (uint256 j = log.topics.length - 1; j < 4; ++j) {
        row = string.concat(row, "0x0,");
      }

      vm.writeLine(filePath, row);
    }
  }
}
