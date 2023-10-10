// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";
import { SD59x18, convert, wrap } from "prb-math/SD59x18.sol";

import { DrawAgent } from "../../src/agent/Draw.sol";
import { EthereumEnvironment, RngAuctionConfig } from "../../src/environment/Ethereum.sol";

import { SD59x18OverTime } from "../../src/SD59x18OverTime.sol";

import { UintOverTime } from "../utils/UintOverTime.sol";
import { BaseTest } from "./Base.t.sol";

contract EthereumTest is BaseTest {
  string simulatorCsv;

  uint256 duration;
  uint256 timeStep = 20 minutes;
  uint256 startTime;
  uint48 firstDrawOpensAt;

  uint256 totalValueLocked;
  uint256 apr = 0.025e18; // 2.5%
  // uint256 numUsers = 1;

  SD59x18OverTime public exchangeRateOverTime; // Prize Token to Underlying Token

  PrizePoolConfig public prizePoolConfig;
  RngAuctionConfig public rngAuctionConfig;
  EthereumEnvironment public env;

  DrawAgent public drawAgent;

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

    rngAuctionConfig = RngAuctionConfig({
      sequenceOffset: _getRngAuctionSequenceOffset(firstDrawOpensAt),
      auctionDuration: AUCTION_DURATION,
      auctionTargetTime: AUCTION_TARGET_TIME,
      firstAuctionTargetRewardFraction: FIRST_AUCTION_TARGET_REWARD_FRACTION
    });

    env = new EthereumEnvironment();
    env.initialize(prizePoolConfig, rngAuctionConfig);

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

  function testEthereum() public noGasMetering recordEvents {
    // env.setApr(aprOverTime.get(startTime));

    initOutputFileCsv();

    for (uint256 i = startTime; i < startTime + duration; i += timeStep) {
      vm.warp(i);
      vm.roll(block.number + 1);

      // Let agents do their thing
      // env.setApr(aprOverTime.get(i));
      drawAgent.check();

      // Log data
      logToCsv(
        SimulatorLog({
          drawId: env.prizePool().getLastAwardedDrawId(),
          timestamp: block.timestamp,
          apr: aprOverTime.get(i),
          tvl: totalValueLocked
        })
      );
    }

    printDraws();
  }

  function printDraws() public view {
    uint256 totalDraws = (block.timestamp - firstDrawOpensAt) / DRAW_PERIOD_SECONDS;
    uint256 missedDraws = (totalDraws) - drawAgent.drawCount();
    console2.log("");
    console2.log("Expected draws", totalDraws);
    console2.log("Actual draws", drawAgent.drawCount());
    console2.log("Missed Draws", missedDraws);
  }

  ////////////////////////// CSV LOGGING //////////////////////////

  struct SimulatorLog {
    uint256 drawId;
    uint256 timestamp;
    uint256 apr;
    uint256 tvl;
  }

  // Clears and logs the CSV headers to the file
  function initOutputFileCsv() public {
    simulatorCsv = string.concat(vm.projectRoot(), "/data/simulatorOut.csv");
    vm.writeFile(simulatorCsv, "");
    vm.writeLine(simulatorCsv, "Draw ID, Timestamp, APR, TVL");
  }

  function logToCsv(SimulatorLog memory log) public {
    vm.writeLine(
      simulatorCsv,
      string.concat(
        vm.toString(log.drawId),
        ",",
        vm.toString(log.timestamp),
        ",",
        vm.toString(log.apr),
        ",",
        vm.toString(log.tvl)
      )
    );
  }
}
