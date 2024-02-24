// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { ClaimerAgent } from "../../src/agent/ClaimerAgent.sol";
import { DrawAgent } from "../../src/agent/DrawAgent.sol";
import { LiquidatorAgent } from "../../src/agent/LiquidatorAgent.sol";

import { SingleChainEnvironment } from "../../src/environment/SingleChainEnvironment.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { Config } from "../../src/utils/Config.sol";
import { Utils } from "../../src/utils/Utils.sol";

contract SingleChainTest is CommonBase, StdCheats, Test, Utils {
  using SafeCast for uint256;

  // NOTE: Order matters for ABI decode.
  struct HistoricApr {
    uint256 apr;
    uint256 timestamp;
  }

  string simulatorCsvFile = string.concat(vm.projectRoot(), "/data/singleChainSimulatorOut.csv");
  string simulatorCsvColumns =
    "Draw ID, Timestamp, Available Yield, Available Prize Vault Shares, Required Prize Tokens, Prize Pool Reserve, Pending Reserve Contributions, APR, TVL";

  uint256 startTime;

  SingleChainEnvironment public env;
  Config public config;
  ClaimerAgent public claimerAgent;
  DrawAgent public drawAgent;
  LiquidatorAgent public liquidatorAgent;

  function setUp() public {
    startTime = block.timestamp + 10000 days;
    vm.warp(startTime);
    config = new Config();
    config.load(vm.envString("CONFIG"));

    initOutputFileCsv(simulatorCsvFile, simulatorCsvColumns);

    console2.log("Setting up at timestamp: ", block.timestamp, "day:", block.timestamp / 1 days);

    env = new SingleChainEnvironment(config);

    claimerAgent = new ClaimerAgent(env);
    drawAgent = new DrawAgent(env);
    liquidatorAgent = new LiquidatorAgent(env);
  }

  function testSingleChain() public noGasMetering recordEvents {
    uint256 duration = (config.simulation().durationDraws+2) * config.prizePool().drawPeriodSeconds;
    uint256 timeStep = config.simulation().timeStep;
    for (uint256 i = startTime; i <= startTime + duration; i += timeStep) {
      vm.warp(i);
      vm.roll(block.number + 1);

      // Cache data at beginning of tick
      uint256 availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
      // console2.log("availableYield %e ", availableYield);
      // console2.log("elapsed time: ", i - startTime);
      uint256 availablePrizeVaultShares = env.pair().maxAmountOut();
      uint256 prizePoolReserve = env.prizePool().reserve();
      uint256 requiredPrizeTokens = availablePrizeVaultShares != 0
        ? env.pair().computeExactAmountIn(availablePrizeVaultShares)
        : 0;

      uint256 pendingReserveContributions = env.prizePool().pendingReserveContributions();

      // Let agents do their thing
      env.updateApr();
      env.mintYield();

      liquidatorAgent.check(config.wethUsdValueOverTime().get(block.timestamp), config.poolUsdValueOverTime().get(block.timestamp));
      drawAgent.check();
      claimerAgent.check();

      uint256[] memory logs = new uint256[](9);
      logs[0] = env.prizePool().getLastAwardedDrawId();
      logs[1] = block.timestamp;
      logs[2] = availableYield;
      logs[3] = availablePrizeVaultShares;
      logs[4] = requiredPrizeTokens;
      logs[5] = prizePoolReserve;
      logs[6] = pendingReserveContributions;
      logs[7] = config.aprOverTime().get(i);
      logs[8] = 0;

      logUint256ToCsv(simulatorCsvFile, logs);

      // console2.log("TOTAL FEE TO USE TO BURN: %e", env.prizePool().rewardBalance(address(env.feeBurner())));
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

  function printLiquidity() public view {
    uint reserve = env.prizePool().reserve() + env.prizePool().pendingReserveContributions();
    uint totalLiquidity = env.prizePool().getTotalContributedBetween(1, env.prizePool().getOpenDrawId());
    uint finalPrizeLiquidity = env.prizePool().accountedBalance() - reserve;
    SD59x18 wethUsdValue = config.wethUsdValueOverTime().get(block.timestamp);
    SD59x18 poolUsdValue = config.poolUsdValueOverTime().get(block.timestamp);
    console2.log("");
    console2.log("Total liquidity (WETH): ", formatTokens(totalLiquidity, wethUsdValue));
    console2.log("Total burned (POOL): ", formatTokens(liquidatorAgent.burnedPool(), poolUsdValue));
    console2.log("Final prize liquidity (WETH)", formatTokens(finalPrizeLiquidity, wethUsdValue));
    console2.log("Final reserve liquidity (WETH)", formatTokens(reserve, wethUsdValue));
  }

  function printDraws() public view {
    uint delta = block.timestamp - (config.prizePool().firstDrawOpensAt + config.prizePool().drawPeriodSeconds);
    uint256 totalDraws = delta / env.prizePool().drawPeriodSeconds();
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
    console2.log("Average fee per claim (WETH): ", formatTokens(averageFeePerClaim, config.wethUsdValueOverTime().get(block.timestamp)));
    console2.log("");
    console2.log("Start draw cost (WETH): ", formatTokens(config.gas().startDrawCostInEth, config.wethUsdValueOverTime().get(block.timestamp)));
    console2.log("Award draw cost (WETH): ", formatTokens(config.gas().awardDrawCostInEth, config.wethUsdValueOverTime().get(block.timestamp)));
    console2.log("Claim cost (WETH): \t  ", formatTokens(config.gas().claimCostInEth, config.wethUsdValueOverTime().get(block.timestamp)));
    console2.log("Liq. cost (WETH): \t  ", formatTokens(config.gas().liquidationCostInEth, config.wethUsdValueOverTime().get(block.timestamp)));
  }

  function printPrizeSummary() public view {
    console2.log("");
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
    console2.log("");
    uint8 numTiers = env.prizePool().numberOfTiers();
    console2.log("Last awarded draw id: %s", env.prizePool().getLastAwardedDrawId());
    console2.log("Last awarded draw claim count: %s", env.prizePool().claimCount());
    console2.log("Next number of tiers: %s", env.prizePool().estimateNextNumberOfTiers());
    console2.log("Final number of tiers: %s", numTiers);
    for (uint8 tier = 0; tier < numTiers; tier++) {
      console2.log(
        "Final prize size for tier",
        tier,
        "is",
        formatTokens(env.prizePool().getTierPrizeSize(tier), config.wethUsdValueOverTime().get(block.timestamp))
      );
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

  function formatTokens(uint256 value, SD59x18 exchangeRate) public view returns(string memory) {
    string memory wholePart = "";
    string memory decimalPart = "";

    uint256 wholeNum = value / 1e18;
    uint256 decimalNum = value % 1e18 / 1e9; // remove the last 9 decimals

    wholePart = vm.toString(wholeNum);
    decimalPart = vm.toString(decimalNum);

    // show 9 decimals
    while(bytes(decimalPart).length < 9) {
      decimalPart = string.concat("0", decimalPart);
    }

    string memory usdCentsPart = "";
    uint256 amountInUSD = uint256(convert(convert(int256(value)).mul(exchangeRate)));
    uint256 usdWhole = amountInUSD / (1e2);
    uint256 usdCentsWhole = amountInUSD % (1e2);
    usdCentsPart = vm.toString(usdCentsWhole);

    // show 2 decimals
    while(bytes(usdCentsPart).length < 2) {
      usdCentsPart = string.concat("0", usdCentsPart);
    }

    return string.concat(wholePart, ".", decimalPart, " ($", vm.toString(usdWhole), ".", usdCentsPart, ")");
  }
}
