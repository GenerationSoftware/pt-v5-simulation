// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

import {
  RngBlockhash,
  DrawManager,
  SingleChainEnvironment,
  PrizePool
} from "../environment/SingleChain.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";
import { Utils } from "../utils/Utils.sol";

contract DrawAgent is Config, Constant, StdCheats, Utils {
  string relayCostCsvFile = string.concat(vm.projectRoot(), "/data/relayCost.csv");
  string relayCostCsvColumns =
    "Draw ID, Timestamp, Awarding Cost, Awarding Profit, Relay Cost, Relay Profit";

  SingleChainEnvironment public env;

  uint256 public drawCount;
  uint256 public constant SEED = 0x23423;

  constructor(SingleChainEnvironment _env) {
    env = _env;

    initOutputFileCsv(relayCostCsvFile, relayCostCsvColumns);
  }

  function check() public returns (uint256) {
    DrawManager drawManager = env.drawManager();
    RngBlockhash rng = env.rng();
    PrizePool prizePool = env.prizePool();

    uint256 startDrawCost = env.gasConfig().startDrawCostInEth;
    uint256 minimumStartDrawProfit = getMinimumProfit(startDrawCost);
    uint256 startDrawProfit;

    // console2.log("Draw startDrawCost %e", startDrawCost);
    // console2.log("Draw minimumStartDrawProfit %e", minimumStartDrawProfit);

    if (drawManager.canStartDraw()) {
      uint fee = drawManager.startDrawFee();
      // console2.log("Draw startDrawFee %e", fee);
      startDrawProfit = fee < startDrawCost ? 0 : fee - startDrawCost;
      if (startDrawProfit >= minimumStartDrawProfit) {
        (uint32 requestId,) = rng.requestRandomNumber();
        drawManager.startDraw(address(this), requestId);
        // console2.log("Draw STARTED", prizePool.getDrawIdToAward());
      }
    } else {
      // console2.log("Draw cannot start draw");
    }

    uint256 awardDrawCost = env.gasConfig().awardDrawCostInEth;
    uint256 minimumAwardDrawProfit = getMinimumProfit(awardDrawCost);
    uint256 awardDrawProfit;

    if (drawManager.canAwardDraw()) {
      // console2.log("Draw CAN AWARD");
      uint fee = drawManager.awardDrawFee();
      // console2.log("Draw awardDraw fee %e", fee);
      awardDrawProfit = fee < awardDrawCost ? 0 : fee - awardDrawCost;
      if (awardDrawProfit >= minimumAwardDrawProfit) {
        drawManager.awardDraw(address(this));
        drawCount++;
        // console2.log("Draw AWARDED", prizePool.getLastAwardedDrawId());

        uint256[] memory logs = new uint256[](6);
        logs[0] = prizePool.getLastAwardedDrawId();
        logs[1] = block.timestamp;
        logs[2] = startDrawCost;
        logs[3] = startDrawProfit;
        logs[4] = awardDrawCost;
        logs[5] = awardDrawProfit;

        logUint256ToCsv(relayCostCsvFile, logs);
      }
    }

    return prizePool.getLastAwardedDrawId();
  }

  function getMinimumProfit(uint256 _cost) public pure returns (uint256) {
    return (_cost + (_cost / 10)) - _cost; // require 10% profit
  }
}
