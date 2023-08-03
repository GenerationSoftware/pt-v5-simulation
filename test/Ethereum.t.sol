// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

import { Environment, PrizePoolConfig, CgdaLiquidatorConfig, DaLiquidatorConfig, ClaimerConfig, GasConfig } from "../src/Environment.sol";
import { SimulatorTest } from "../src/SimulatorTest.sol";
import { ClaimerAgent } from "../src/ClaimerAgent.sol";
import { DrawAgent } from "../src/DrawAgent.sol";
import { LiquidatorAgent } from "../src/LiquidatorAgent.sol";
import { SD59x18OverTime } from "../src/SD59x18OverTime.sol";
import { UintOverTime } from "../src/UintOverTime.sol";

contract EthereumTest is SimulatorTest {
  string simulatorCsv;

  uint32 drawPeriodSeconds = 1 days;
  uint32 grandPrizePeriodDraws = 365;

  uint duration = 30 days + 0.5 days;
  uint timeStep = 5 minutes;
  uint startTime;

  uint totalValueLocked;
  uint apr = 0.015e18;
  uint numUsers = 1;

  SD59x18OverTime public exchangeRateOverTime; // Prize Token to Underlying Token
  UintOverTime public aprOverTime;

  PrizePoolConfig public prizePoolConfig;
  ClaimerConfig public claimerConfig;
  GasConfig public gasConfig;
  Environment public env;

  ClaimerAgent public claimerAgent;
  LiquidatorAgent public liquidatorAgent;
  DrawAgent public drawAgent;

  function setUp() public {
    startTime = block.timestamp + 400 days;
    vm.warp(startTime);

    totalValueLocked = vm.envUint("TVL") * 1e18;
    console2.log("TVL: ", vm.envUint("TVL"));
    if (totalValueLocked == 0) {
      revert("Please define TVL env var > 0");
    }

    initOutputFileCsv();

    setUpExchangeRate();
    // setUpExchangeRateFromJson();

    // setUpApr();
    setUpAprFromJson();

    console2.log("Setting up at timestamp: ", block.timestamp, "day:", block.timestamp / 1 days);
    console2.log("Draw Period (sec): ", drawPeriodSeconds);
    console2.log("");

    prizePoolConfig = PrizePoolConfig({
      grandPrizePeriodDraws: grandPrizePeriodDraws,
      drawPeriodSeconds: drawPeriodSeconds,
      firstDrawStartsAt: uint64(startTime),
      numberOfTiers: 3,
      tierShares: 100,
      canaryShares: 30,
      reserveShares: 50,
      claimExpansionThreshold: UD2x18.wrap(0.8e18),
      smoothing: SD1x18.wrap(0.3e18)
    });

    claimerConfig = ClaimerConfig({
      minimumFee: 0.1e18,
      maximumFee: 1000e18,
      timeToReachMaxFee: drawPeriodSeconds / 7,
      maxFeePortionOfPrize: UD2x18.wrap(0.2e18)
    });

    // gas price is currently 50 gwei of ether.
    // ether is worth 1800 POOL
    // 50 * 1800 = 90000 POOL
    // On Optimism gas is 0.000001588 gwei
    // 0.000001588 * 1800 = 0.0028584 POOL
    gasConfig = GasConfig({
      gasPriceInPrizeTokens: 700 gwei,
      gasUsagePerClaim: 150_000,
      gasUsagePerLiquidation: 500_000,
      gasUsagePerStartDraw: 152_473,
      gasUsagePerCompleteDraw: 66_810,
      gasUsagePerDispatchDraw: 250_000
    });

    env = new Environment();
    env.initialize(prizePoolConfig, claimerConfig, gasConfig);

    ///////////////// Liquidator /////////////////
    // Initialize one of the liquidators. Comment the other out.

    env.initializeCgdaLiquidator(
      CgdaLiquidatorConfig({
        decayConstant: wrap(0.001e18),
        exchangeRatePrizeTokenToUnderlying: exchangeRateOverTime.get(startTime),
        periodLength: drawPeriodSeconds,
        periodOffset: uint32(startTime),
        targetFirstSaleTime: drawPeriodSeconds / 2
      })
    );

    //////////////////////////////////////////////

    claimerAgent = new ClaimerAgent(env, vm);
    liquidatorAgent = new LiquidatorAgent(env, vm);
    drawAgent = new DrawAgent(env);
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
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 2), wrap(1.5e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 4), wrap(2e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 6), wrap(4e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 8), wrap(3e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 10), wrap(1e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 12), wrap(5e17));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 14), wrap(1e17));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 16), wrap(5e16));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 18), wrap(1e16));

    // Custom test case
    exchangeRateOverTime.add(startTime, wrap(1e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 1), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 2), wrap(1.05e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 3), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 4), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 5), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 6), wrap(1.12e18));
    // exchangeRateOverTime.add(startTime + (drawPeriodSeconds * 7), wrap(1.5e18));
  }

  // NOTE: Order matters for ABI decode.
  struct HistoricApr {
    uint256 apr;
    uint256 timestamp;
  }

  function setUpApr() public {
    aprOverTime = new UintOverTime();

    // Realistic test case
    aprOverTime.add(startTime, 0.05e18);
    aprOverTime.add(startTime + drawPeriodSeconds, 0.10e18);
  }

  function setUpAprFromJson() public {
    aprOverTime = new UintOverTime();

    string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicAaveApr.json");
    string memory jsonData = vm.readFile(jsonFile);
    // NOTE: Options for APR are: .usd or .eth
    bytes memory usdData = vm.parseJson(jsonData, "$.usd");
    HistoricApr[] memory aprData = abi.decode(usdData, (HistoricApr[]));

    uint256 initialTimestamp = aprData[0].timestamp;
    for (uint256 i = 0; i < aprData.length; i++) {
      HistoricApr memory rowData = aprData[i];
      uint256 timeElapsed = rowData.timestamp - initialTimestamp;

      aprOverTime.add(startTime + timeElapsed, rowData.apr);
    }
  }

  function testEthereum() public noGasMetering recordEvents {
    env.addUsers(numUsers, totalValueLocked / numUsers);

    env.setApr(aprOverTime.get(startTime));

    // initOutputFileCsv();

    for (uint i = startTime; i < startTime + duration; i += timeStep) {
      vm.warp(i);
      vm.roll(block.number+1);

      // Cache data at beginning of tick
      uint availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
      uint availableVaultShares = env.pair().maxAmountOut();
      uint requiredPrizeTokens = env.pair().computeExactAmountIn(availableVaultShares);
      uint prizePoolReserve = env.prizePool().reserve();

      // uint unrealizedReserve = env.prizePool().reserveForNextDraw();
      // string memory valuesPart1 = string.concat(
      //     vm.toString(i), ",",
      //     vm.toString(drawAgent.drawCount()), ",",
      //     vm.toString((i - startTime) / drawPeriodSeconds), ",",
      //     vm.toString(availableYield), ",",
      //     vm.toString(availableYield / 1e18), ",",
      //     vm.toString(availableVaultShares), ",",
      //     vm.toString(availableVaultShares / 1e18), ",",
      //     vm.toString(requiredPrizeTokens), ",",
      //     vm.toString(requiredPrizeTokens / 1e18), ","
      // );
      // // split to avoid stack too deep
      // string memory valuesPart2 = string.concat(
      //     vm.toString(prizePoolReserve), ",",
      //     vm.toString(prizePoolReserve / 1e18)
      // );
      // vm.writeLine(runStatsOut,string.concat(valuesPart1,valuesPart2));

      // Let agents do their thing
      env.setApr(aprOverTime.get(i));
      env.mintYield();
      claimerAgent.check();
      liquidatorAgent.check(exchangeRateOverTime.get(block.timestamp));
      drawAgent.check();

      // Log data
      logToCsv(
        SimulatorLog({
          drawId: env.prizePool().getLastClosedDrawId(),
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

    printDraws();
    printMissedPrizes();
    printTotalNormalPrizes();
    printTotalCanaryPrizes();
    printTotalClaimFees();
    printPrizeSummary();
    printFinalPrizes();
  }

  function printDraws() public {
    uint totalDraws = duration / drawPeriodSeconds;
    uint missedDraws = (totalDraws) - drawAgent.drawCount();
    console2.log("");
    console2.log("Expected draws", totalDraws);
    console2.log("Actual draws", drawAgent.drawCount());
    console2.log("Missed Draws", missedDraws);
  }

  function printMissedPrizes() public {
    uint lastDrawId = env.prizePool().getLastClosedDrawId();
    for (uint32 drawId = 0; drawId <= lastDrawId; drawId++) {
      uint numTiers = claimerAgent.drawNumberOfTiers(drawId);
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

  function printTotalNormalPrizes() public {
    uint normalComputed = claimerAgent.totalNormalPrizesComputed();
    uint normalClaimed = claimerAgent.totalNormalPrizesClaimed();
    console2.log("");
    console2.log("Number of normal prizes", normalComputed);
    console2.log("Number of prizes claimed", normalClaimed);
    console2.log("Missed normal prizes", normalComputed - normalClaimed);
  }

  function printTotalCanaryPrizes() public {
    uint canaryComputed = claimerAgent.totalCanaryPrizesComputed();
    uint canaryClaimed = claimerAgent.totalCanaryPrizesClaimed();
    console2.log("");
    console2.log("Number of canary prizes", canaryComputed);
    console2.log("Number of canary prizes claimed", canaryClaimed);
    console2.log("Missed canary prizes", canaryComputed - canaryClaimed);
  }

  function printTotalClaimFees() public {
    uint totalPrizes = claimerAgent.totalNormalPrizesClaimed() +
      claimerAgent.totalCanaryPrizesClaimed();
    uint averageFeePerClaim = totalPrizes > 0 ? claimerAgent.totalFees() / totalPrizes : 0;
    console2.log("");
    console2.log("Average fee per claim (cents): ", averageFeePerClaim / 1e16);
  }

  function printPrizeSummary() public {
    uint8 maxTiers;
    uint lastDrawId = env.prizePool().getLastClosedDrawId();
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

  function printFinalPrizes() public {
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
    uint drawId;
    uint timestamp;
    uint availableYield;
    uint availableVaultShares;
    uint requiredPrizeTokens;
    uint prizePoolReserve;
    uint apr;
    uint tvl;
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
