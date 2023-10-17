// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { StdCheats } from "forge-std/StdCheats.sol";

import {
  IMessageDispatcherOptimism
} from "erc5164-interfaces/interfaces/IMessageDispatcherOptimism.sol";
import { AuctionResult } from "pt-v5-draw-auction/interfaces/IAuction.sol";
import {
  IRngAuctionRelayListener
} from "pt-v5-draw-auction/interfaces/IRngAuctionRelayListener.sol";
import { RemoteOwner } from "remote-owner/RemoteOwner.sol";

import {
  BaseEnvironment,
  PrizePool,
  RngAuction,
  RngAuctionRelayerDirect,
  RngRelayAuction
} from "../environment/Base.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";
import { Utils } from "../utils/Utils.sol";

contract DrawAgent is Config, Constant, StdCheats, Utils {
  string relayCostCsvFile = string.concat(vm.projectRoot(), "/data/relayCost.csv");
  string relayCostCsvColumns =
    "Draw ID, Timestamp, Awarding Cost, Awarding Profit, Relay Cost, Relay Profit";

  BaseEnvironment public env;
  EthereumGasConfig gasConfig = ethereumGasConfig();

  IMessageDispatcherOptimism messageDispatcherOptimism =
    IMessageDispatcherOptimism(makeAddr("messageDispatcherOptimism"));

  IRngAuctionRelayListener remoteRngAuctionRelayListener =
    IRngAuctionRelayListener(makeAddr("remoteRngAuctionRelayListener"));

  RemoteOwner remoteOwner = RemoteOwner(payable(makeAddr("remoteOwner")));

  uint256 public drawCount;
  uint256 public constant SEED = 0x23423;

  constructor(BaseEnvironment _env) {
    env = _env;

    initOutputFileCsv(relayCostCsvFile, relayCostCsvColumns);
  }

  function check(uint256 _previousSequenceId) public returns (uint256) {
    // awarding cost = start draw cost in POOL tokens + RNG cost in POOL tokens
    uint256 awardingCost = (gasConfig.gasUsagePerStartDraw * gasConfig.gasPriceInPrizeTokens) +
      gasConfig.rngCostInPrizeTokens;
    uint256 minimumAwardingProfit = getMinimumProfit(awardingCost);
    uint256 awardingProfit;

    uint256 relayCost = gasConfig.gasUsagePerRelayDraw * gasConfig.gasPriceInPrizeTokens;
    uint256 minimumRelayProfit = getMinimumProfit(relayCost);
    uint256 relayProfit;

    PrizePool prizePool = env.prizePool();
    RngAuction rngAuction = env.rngAuction();
    RngAuctionRelayerDirect rngAuctionRelayerDirect = env.rngAuctionRelayerDirect();
    RngRelayAuction rngRelayAuction = env.rngRelayAuction();

    uint32 lastSequenceId = rngAuction.lastSequenceId();

    if (rngAuction.isAuctionOpen() && rngAuction.openSequenceId() != _previousSequenceId) {
      AuctionResult[] memory auctionResults = new AuctionResult[](1);
      auctionResults[0] = AuctionResult({
        rewardFraction: rngAuction.currentFractionalReward(),
        recipient: address(this)
      });

      uint256[] memory rewards = rngRelayAuction.computeRewards(auctionResults);
      awardingProfit = rewards[0] > awardingCost ? rewards[0] - awardingCost : 0;

      if (awardingProfit >= minimumAwardingProfit) {
        rngAuction.startRngRequest(address(this));

        uint256[] memory logs = new uint256[](6);
        logs[0] = prizePool.getLastAwardedDrawId() + 1;
        logs[1] = block.timestamp;
        logs[2] = awardingCost;
        logs[3] = awardingProfit;
        logs[4] = relayCost;
        logs[5] = relayProfit;

        logUint256ToCsv(relayCostCsvFile, logs);
      }
    }

    uint64 completedAt;
    bool isAuctionOpen;

    if (
      lastSequenceId > 0 && // if there is a last sequence id
      rngAuction.isRngComplete() // and it's ready
    ) {
      (, /* uint256 randomNumber */ completedAt) = rngAuction.getRngResults();
      isAuctionOpen = rngRelayAuction.isAuctionOpen(lastSequenceId, completedAt); // and the last sequence has not completed yet
    }

    if (isAuctionOpen) {
      // Compute reward
      AuctionResult[] memory auctionResults = new AuctionResult[](2);
      auctionResults[0] = rngAuction.getLastAuctionResult();
      auctionResults[1] = AuctionResult({
        rewardFraction: rngRelayAuction.computeRewardFraction(
          uint64(block.timestamp - completedAt)
        ),
        recipient: address(this)
      });

      uint256[] memory rewards = rngRelayAuction.computeRewards(auctionResults);
      relayProfit = rewards[1] > relayCost ? rewards[1] - relayCost : 0;

      if (relayProfit >= minimumRelayProfit) {
        drawCount++;
        rngAuctionRelayerDirect.relay(rngRelayAuction, address(this));

        uint256[] memory logs = new uint256[](6);
        logs[0] = prizePool.getLastAwardedDrawId();
        logs[1] = block.timestamp;
        logs[2] = awardingCost;
        logs[3] = awardingProfit;
        logs[4] = relayCost;
        logs[5] = relayProfit;

        logUint256ToCsv(relayCostCsvFile, logs);
      }
    }

    return rngAuction.lastSequenceId();
  }

  function getMinimumProfit(uint256 _cost) public pure returns (uint256) {
    return (_cost + (_cost / 10)) - _cost; // require 10% profit
  }
}
