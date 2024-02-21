// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { SD59x18, wrap, convert } from "prb-math/SD59x18.sol";

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

  constructor() {}

  // APR
  // function setUpExchangeRateFromJson(uint256 _startTime) public {
  //   wethUsdValueOverTime = new SD59x18OverTime();

  //   string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicPrices.json");
  //   string memory jsonData = vm.readFile(jsonFile);
  //   // NOTE: Options for exchange rate are: .usd or .eth
  //   bytes memory usdData = vm.parseJson(jsonData, "$.usd");
  //   HistoricPrice[] memory prices = abi.decode(usdData, (HistoricPrice[]));

  //   uint256 initialTimestamp = prices[0].timestamp;
  //   for (uint256 i = 0; i < prices.length; i++) {
  //     HistoricPrice memory priceData = prices[i];
  //     uint256 timeElapsed = priceData.timestamp - initialTimestamp;

  //     wethUsdValueOverTime.add(
  //       _startTime + timeElapsed,
  //       SD59x18.wrap(int256(priceData.exchangeRate * 1e9))
  //     );
  //   }
  // }

  function computeGasCostInUsd(SD59x18 ethValueUsd, uint256 gasCostInEth) public view returns (SD59x18) {
    return ethValueUsd.mul(convert(int(gasCostInEth)));
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
