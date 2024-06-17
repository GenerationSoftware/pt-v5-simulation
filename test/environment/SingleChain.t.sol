// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { console2 } from "forge-std/console2.sol";

import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { ClaimerAgent } from "../../src/agent/ClaimerAgent.sol";
import { DrawAgent, DrawDetail } from "../../src/agent/DrawAgent.sol";
import { LiquidatorAgent } from "../../src/agent/LiquidatorAgent.sol";

import { SingleChainEnvironment } from "../../src/environment/SingleChainEnvironment.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { Config, USD_DECIMALS } from "../../src/utils/Config.sol";
import { Utils } from "../../src/utils/Utils.sol";

import { DrawLog, Logger } from "../../src/utils/Logger.sol";

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
  ClaimerAgent public vaultClaimerAgent;
  ClaimerAgent public poolPrizeVaultClaimerAgent;
  ClaimerAgent public boostClaimerAgent;
  DrawAgent public drawAgent;
  LiquidatorAgent public liquidatorAgent;

  Logger public logger;

  mapping(uint24 drawId => DrawLog) public drawLogs;

  function setUp() public {
    startTime = block.timestamp + 10000 days;
    vm.warp(startTime);
    config = new Config();
    config.load(vm.envString("CONFIG"));
    logger = new Logger(vm.envString("OUTPUT"));

    initOutputFileCsv(simulatorCsvFile, simulatorCsvColumns);

    env = new SingleChainEnvironment(config);
    vaultClaimerAgent = new ClaimerAgent(env, address(env.vault()), env.allUsers());
    poolPrizeVaultClaimerAgent = new ClaimerAgent(env, address(env.poolPrizeVault()), env.allUsers());
    address[] memory boostUsers = new address[](1);
    boostUsers[0] = address(env.gpBoostHook());
    boostClaimerAgent = new ClaimerAgent(env, address(env.gpBoostHook()), boostUsers);
    drawAgent = new DrawAgent(env);
    liquidatorAgent = new LiquidatorAgent(env);
  }

  function testSingleChain() public noGasMetering recordEvents {
    PrizePool prizePool = env.prizePool();

    uint256 duration = (config.simulation().durationDraws+2) * config.prizePool().drawPeriodSeconds;
    for (uint256 i = startTime; i <= startTime + duration; i += config.simulation().timeStep) {
      vm.warp(i);
      vm.roll(block.number + 2);

      // Let agents do their thing
      env.mintYield();

      uint24 finalizedDrawId = env.prizePool().getLastAwardedDrawId();
      DrawLog memory finalizedDrawLog = drawLogs[finalizedDrawId];
      finalizedDrawLog.apr = env.updateApr();
      liquidatorAgent.check(config.wethUsdValueOverTime().get(block.timestamp), config.poolUsdValueOverTime().get(block.timestamp));

      if (drawAgent.check()) {
        uint24 closedDrawId = env.prizePool().getLastAwardedDrawId();
        drawLogs[closedDrawId] = updateDrawLog(drawLogs[closedDrawId], closedDrawId);

        if (config.simulation().gpBoostPerDraw > 0 && config.simulation().gpBoostPerDrawLastDraw > closedDrawId) {
          env.prizeToken().mint(address(this), config.simulation().gpBoostPerDraw);
          env.prizeToken().approve(address(env.gpBoostHook()), config.simulation().gpBoostPerDraw);
          env.gpBoostHook().contributePrizeTokens(config.simulation().gpBoostPerDraw);
        }

        if (finalizedDrawId > 0) {
          for (uint8 t = 0; t < finalizedDrawLog.numberOfTiers; t++) {
            finalizedDrawLog.claimedPrizes[t] = vaultClaimerAgent.drawTierClaimedPrizeCounts(finalizedDrawId, t) + poolPrizeVaultClaimerAgent.drawTierClaimedPrizeCounts(finalizedDrawId, t);
            finalizedDrawLog.computedPrizes[t] = vaultClaimerAgent.drawTierComputedPrizeCounts(finalizedDrawId, t) + poolPrizeVaultClaimerAgent.drawTierComputedPrizeCounts(finalizedDrawId, t);
          }  
        }

        drawLogs[finalizedDrawId] = finalizedDrawLog;
      }
      vaultClaimerAgent.check();
      boostClaimerAgent.check();
      poolPrizeVaultClaimerAgent.check();
    }

    dumpLogs();

    env.removeUsers();

    printDraws();
    printMissedPrizes();
    printTotalNormalPrizes();
    printTotalClaimFees();
    printPrizeSummary();
    printFinalPrizes();
    printLiquidity();
  }

  function updateDrawLog(DrawLog memory closedDrawLog, uint24 closedDrawId) internal returns (DrawLog memory) {
    PrizePool prizePool = env.prizePool();
    DrawDetail memory closedDrawDetail = drawAgent.drawDetails(closedDrawId);
    SD59x18 wethValue = config.wethUsdValueOverTime().get(block.timestamp);
    closedDrawLog.drawId = closedDrawId;
    closedDrawLog.numberOfTiers = closedDrawDetail.numberOfTiers;
    closedDrawLog.startDrawReward = closedDrawDetail.startDrawReward;
    closedDrawLog.finishDrawReward = closedDrawDetail.finishDrawReward;
    closedDrawLog.totalLiquidationAmountOutUsd = formatUsd(liquidatorAgent.totalAmountOutPerDraw(closedDrawId), config.poolUsdValueOverTime().get(block.timestamp));
    closedDrawLog.totalLiquidationAmountInUsd = formatUsd(liquidatorAgent.totalAmountInPerDraw(closedDrawId), wethValue);
    closedDrawLog.reserveAmountContributedUsd = formatUsd(prizePool.getContributedBetween(env.drawManager().vaultBeneficiary(), closedDrawId, closedDrawId), wethValue);
    closedDrawLog.hookContributed = formatUsd(prizePool.getContributedBetween(address(env.gpBoostHook()), closedDrawId, closedDrawId), wethValue);
    closedDrawLog.totalContributed = formatUsd(prizePool.getTotalContributedBetween(closedDrawId, closedDrawId), wethValue);
    for (uint8 t = 0; t < closedDrawLog.numberOfTiers; t++) {
      closedDrawLog.tierLiquidityRemaining[t] = prizePool.getTierRemainingLiquidity(t);
      closedDrawLog.tierPrizeSizes[t] = prizePool.getTierPrizeSize(t);
      closedDrawLog.tierPrizeSizesUsd[t] = formatUsd(prizePool.getTierPrizeSize(t), wethValue);
    }
    return closedDrawLog;
  }

  // function updateContributed(DrawLog memory closedDrawLog, uint24 closedDrawId) internal returns (DrawLog memory) {
  //   PrizePool prizePool = env.prizePool();
  //   SD59x18 wethValue = config.wethUsdValueOverTime().get(block.timestamp);
  //   closedDrawLog.reserveAmountContributedUsd = formatUsd(prizePool.getContributedBetween(env.drawManager().vaultBeneficiary(), closedDrawId, closedDrawId), wethValue);
  //   closedDrawLog.hookContributed = formatUsd(prizePool.getContributedBetween(address(env.gpBoostHook()), closedDrawId, closedDrawId), wethValue);
  //   closedDrawLog.totalContributed = formatUsd(prizePool.getTotalContributedBetween(closedDrawId, closedDrawId), wethValue);
  //   return closedDrawLog;
  // }

  function dumpLogs() public {
    for (uint24 drawId = 1; drawId <= env.prizePool().getLastAwardedDrawId(); drawId++) {
      logger.log(drawLogs[drawId]);
    }
  }

  function printMissedPrizes() public view {
    uint24 lastDrawId = env.prizePool().getLastAwardedDrawId();
    for (uint24 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint256 numTiers = vaultClaimerAgent.drawNumberOfTiers(drawId);
      for (uint8 tier = 0; tier < numTiers; tier++) {
        uint256 prizeCount = vaultClaimerAgent.drawTierComputedPrizeCounts(drawId, tier) + poolPrizeVaultClaimerAgent.drawTierComputedPrizeCounts(drawId, tier);
        uint256 claimCount = vaultClaimerAgent.drawTierClaimedPrizeCounts(drawId, tier) + poolPrizeVaultClaimerAgent.drawTierClaimedPrizeCounts(drawId, tier);
        if (claimCount < prizeCount && tier < (numTiers - 1)) { // not last canary tier
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
    uint totalContributedToPoolPrizeVault = env.prizePool().getContributedBetween(address(env.poolPrizeVault()), 1, env.prizePool().getOpenDrawId());
    SD59x18 wethUsdValue = config.wethUsdValueOverTime().get(block.timestamp);
    SD59x18 poolUsdValue = config.poolUsdValueOverTime().get(block.timestamp);
    console2.log("");
    console2.log("Total liquidity (WETH): ", formatTokens(totalLiquidity, wethUsdValue));
    console2.log("Final prize liquidity (WETH)", formatTokens(finalPrizeLiquidity, wethUsdValue));
    console2.log("Final reserve liquidity (WETH)", formatTokens(reserve, wethUsdValue));
    console2.log("Total Contributed for POOL Prize Vault (WETH)", formatTokens(totalContributedToPoolPrizeVault, wethUsdValue));
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
    uint256 normalComputed = vaultClaimerAgent.totalPrizesComputed() + poolPrizeVaultClaimerAgent.totalPrizesComputed();
    uint256 normalClaimed = vaultClaimerAgent.totalPrizesClaimed() + poolPrizeVaultClaimerAgent.totalPrizesClaimed();
    console2.log("");
    console2.log("Number of normal prizes", normalComputed);
    console2.log("Number of prizes claimed", normalClaimed);
    console2.log("Missed total prizes (inc. canary)", normalComputed - normalClaimed);
  }

  function printTotalClaimFees() public view {
    uint256 totalPrizes = vaultClaimerAgent.totalPrizesClaimed() + poolPrizeVaultClaimerAgent.totalPrizesClaimed();
    uint256 averageFeePerClaim = totalPrizes > 0 ? (vaultClaimerAgent.totalFees() + poolPrizeVaultClaimerAgent.totalFees()) / totalPrizes : 0;
    console2.log("");
    console2.log("Average fee per claim (WETH): ", formatTokens(averageFeePerClaim, config.wethUsdValueOverTime().get(block.timestamp)));
    console2.log("");
    console2.log("Start draw cost (USD): ", formatUsd(config.gas().startDrawCostInUsd));
    console2.log("Award draw cost (USD): ", formatUsd(config.gas().finishDrawCostInUsd));
    console2.log("Claim cost (USD): \t  ", formatUsd(config.gas().claimCostInUsd));
    console2.log("Liq. cost (USD): \t  ", formatUsd(config.gas().liquidationCostInUsd));
  }

  function printPrizeSummary() public view {
    console2.log("");
    uint8 maxTiers;
    uint24 lastDrawId = env.prizePool().getLastAwardedDrawId();
    for (uint24 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint8 numTiers = vaultClaimerAgent.drawNumberOfTiers(drawId);
      if (numTiers > maxTiers) {
        maxTiers = numTiers;
      }
    }

    uint256[] memory tierPrizeCounts = new uint256[](maxTiers);
    for (uint24 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint8 numTiers = vaultClaimerAgent.drawNumberOfTiers(drawId);
      if (numTiers > maxTiers) {
        maxTiers = numTiers;
      }
      for (uint8 tier = 0; tier < numTiers; tier++) {
        tierPrizeCounts[tier] += vaultClaimerAgent.drawTierClaimedPrizeCounts(drawId, tier) + poolPrizeVaultClaimerAgent.drawTierClaimedPrizeCounts(drawId, tier);
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

    return string.concat(wholePart, ".", decimalPart, " (", formatUsd(value, exchangeRate), ")");
  }

  function formatUsd(uint256 tokens, SD59x18 usdPerToken) public view returns(string memory) {
    uint256 amountInUSD = uint256(convert(convert(int256(tokens)).mul(usdPerToken)));
    return formatUsd(amountInUSD);
  }

  function formatUsd(uint256 amountInUSD) public view returns(string memory) {
    uint256 usdWhole = amountInUSD / (10**USD_DECIMALS);
    uint256 usdCentsWhole = amountInUSD % (10**USD_DECIMALS);
    string memory usdCentsPart = vm.toString(usdCentsWhole);

    while(bytes(usdCentsPart).length < USD_DECIMALS) {
      usdCentsPart = string.concat("0", usdCentsPart);
    }

    return string.concat("$", vm.toString(usdWhole), ".", usdCentsPart, " USD");
  }

}
