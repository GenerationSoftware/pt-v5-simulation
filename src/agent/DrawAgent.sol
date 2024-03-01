// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

import {
  RngBlockhash,
  DrawManager,
  SingleChainEnvironment,
  PrizePool
} from "../environment/SingleChainEnvironment.sol";

import { Config } from "../utils/Config.sol";
import { Utils } from "../utils/Utils.sol";

struct DrawDetail {
  uint8 numberOfTiers;
  uint256 startDrawReward;
  uint256 finishDrawReward;
}

contract DrawAgent is StdCheats, Utils {
  string relayCostCsvFile = string.concat(vm.projectRoot(), "/data/relayCost.csv");
  string relayCostCsvColumns =
    "Draw ID, Timestamp, Awarding Cost, Awarding Profit, Relay Cost, Relay Profit";

  SingleChainEnvironment public env;

  uint256 public drawCount;
  uint256 public constant SEED = 0x23423;

  mapping(uint24 drawId => DrawDetail drawInfo) internal _drawDetails;

  constructor(SingleChainEnvironment _env) {
    env = _env;

    initOutputFileCsv(relayCostCsvFile, relayCostCsvColumns);
  }

  function drawDetails(uint24 drawId) public view returns (DrawDetail memory) {
    return _drawDetails[drawId];
  }

  function willFinishDraw() public view returns (bool) {
    uint256 finishDrawCost = env.config().gas().finishDrawCostInEth;
    uint256 minimumFinishDrawProfit = getMinimumProfit(finishDrawCost);
    uint256 finishDrawProfit;

    if (env.drawManager().canFinishDraw()) {
      // console2.log("Draw CAN AWARD");
      uint fee = env.drawManager().finishDrawReward();
      // console2.log("Draw finishDraw fee %e", fee);
      finishDrawProfit = fee < finishDrawCost ? 0 : fee - finishDrawCost;
      // console2.log("finishDrawCost %e", finishDrawCost);
      return finishDrawProfit >= minimumFinishDrawProfit;
    }

    return false;
  }

  function check() public returns (bool) {
    DrawManager drawManager = env.drawManager();
    RngBlockhash rng = env.rng();
    PrizePool prizePool = env.prizePool();

    uint24 drawId = prizePool.getDrawIdToAward();

    if (drawManager.canStartDraw()) {
      uint fee = drawManager.startDrawReward();
      // console2.log("fee %e", fee);
      uint256 startDrawCost = env.config().gas().startDrawCostInEth;
      // console2.log("cost %e", startDrawCost);
      uint256 startDrawProfit = fee < startDrawCost ? 0 : fee - startDrawCost;
      if (startDrawProfit >= getMinimumProfit(startDrawCost)) {
        // console2.log("started draw", drawId);
        (uint32 requestId,) = rng.requestRandomNumber();
        drawManager.startDraw(address(this), requestId);
        _drawDetails[drawId].startDrawReward = fee;
      }
    } else {
    }

    if (willFinishDraw()) {
      _drawDetails[drawId].numberOfTiers = prizePool.numberOfTiers();
      _drawDetails[drawId].finishDrawReward = drawManager.finishDrawReward();
      // console2.log("Awarding draw ", drawId);
      drawManager.finishDraw(address(this));
      drawCount++;
      return true;
    }

    return false;
  }

  function getMinimumProfit(uint256 _cost) public pure returns (uint256) {
    return (_cost + (_cost / 10)) - _cost; // require 10% profit
  }
}
