// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { SD59x18, wrap } from "prb-math/SD59x18.sol";

import { SD59x18OverTime } from "./SD59x18OverTime.sol";

contract Utils is CommonBase {
  // APR
  struct HistoricPrice {
    uint256 exchangeRate;
    uint256 timestamp;
  }

  // Logging
  struct RawClaimerLog {
    uint256 drawId;
    uint8 tier;
    address[] winners;
    uint32[][] prizeIndices;
    uint256 feesForBatch;
  }

  struct ClaimerLog {
    uint256 drawId;
    uint256 tier;
    address winner;
    uint32 prizeIndex;
    uint256 feesForBatch;
  }

  SD59x18OverTime public exchangeRateOverTime; // Prize Token to Underlying Token

  constructor() {}

  // APR
  function setUpExchangeRateFromJson(uint256 _startTime) public {
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
        _startTime + timeElapsed,
        SD59x18.wrap(int256(priceData.exchangeRate * 1e9))
      );
    }
  }

  function setUpExchangeRate(uint256 _startTime) public {
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
    exchangeRateOverTime.add(_startTime, wrap(1e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 1), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 2), wrap(1.05e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 3), wrap(1.02e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 4), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 5), wrap(0.98e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 6), wrap(1.12e18));
    // exchangeRateOverTime.add(startTime + (DRAW_PERIOD_SECONDS * 7), wrap(1.5e18));
  }

  // Logging
  // Clears and logs the CSV headers to the file
  function initOutputFileCsv(string memory csvFile, string memory csvColumns) public {
    vm.writeFile(csvFile, "");
    vm.writeLine(csvFile, csvColumns);
  }

  function logUint256ToCsv(string memory csvFile, uint256[] memory logs) public {
    string memory log = "";

    for (uint256 i = 0; i < logs.length; i++) {
      log = string.concat(log, vm.toString(logs[i]), i != logs.length - 1 ? "," : "");
    }

    vm.writeLine(csvFile, log);
  }

  function logClaimerToCsv(string memory csvFile, RawClaimerLog memory log) public {
    for (uint256 i = 0; i < log.winners.length; i++) {
      for (uint256 j = 0; j < log.prizeIndices[i].length; j++) {
        ClaimerLog memory claimerLog = ClaimerLog({
          drawId: log.drawId,
          tier: log.tier,
          winner: log.winners[i],
          prizeIndex: log.prizeIndices[i][j],
          feesForBatch: log.feesForBatch
        });

        vm.writeLine(
          csvFile,
          string.concat(
            vm.toString(claimerLog.drawId),
            ",",
            vm.toString(claimerLog.tier),
            ",",
            vm.toString(claimerLog.winner),
            ",",
            vm.toString(claimerLog.prizeIndex),
            ",",
            vm.toString(claimerLog.feesForBatch)
          )
        );
      }
    }
  }
}
