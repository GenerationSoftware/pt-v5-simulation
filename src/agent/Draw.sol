// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { StdCheats } from "forge-std/StdCheats.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

import {
  IMessageDispatcherOptimism
} from "erc5164-interfaces/interfaces/IMessageDispatcherOptimism.sol";
import { AuctionResult } from "pt-v5-draw-auction/interfaces/IAuction.sol";
import {
  IRngAuctionRelayListener
} from "pt-v5-draw-auction/interfaces/IRngAuctionRelayListener.sol";
import { RemoteOwner } from "remote-owner/RemoteOwner.sol";

import {
  EthereumEnvironment,
  RngAuction,
  RngAuctionRelayerRemoteOwner,
  RngRelayAuction
} from "../environment/Ethereum.sol";

import { Config } from "../utils/Config.sol";

contract DrawAgent is Config, StdCheats {
  EthereumEnvironment public env;
  EthereumGasConfig gasConfig = ethereumGasConfig();

  IMessageDispatcherOptimism messageDispatcherOptimism =
    IMessageDispatcherOptimism(makeAddr("messageDispatcherOptimism"));

  IRngAuctionRelayListener remoteRngAuctionRelayListener =
    IRngAuctionRelayListener(makeAddr("remoteRngAuctionRelayListener"));

  RemoteOwner remoteOwner = RemoteOwner(payable(makeAddr("remoteOwner")));

  uint256 public drawCount;
  uint256 public constant SEED = 0x23423;

  constructor(EthereumEnvironment _env) {
    env = _env;
  }

  function check() public {
    // awarding cost = start draw cost in POOL tokens  + RNG cost in POOL tokens
    uint256 awardingCost = (gasConfig.gasUsagePerStartDraw * gasConfig.gasPriceInPrizeTokens) +
      gasConfig.rngCostInPrizeTokens;
    uint256 minimumAwardingProfit = getMinimumProfit(awardingCost);

    uint256 relayCost = gasConfig.gasUsagePerRelayDraw * gasConfig.gasPriceInPrizeTokens;
    uint256 minimumRelayProfit = getMinimumProfit(relayCost);

    uint256 totalCost = awardingCost + relayCost;

    // console2.log("PrizePool hasNextDrawFinished: %s", env.prizePool().hasNextDrawFinished());

    RngAuction rngAuction = env.rngAuction();
    RngAuctionRelayerRemoteOwner rngAuctionRelayerRemoteOwner = env.rngAuctionRelayerRemoteOwner();
    RngRelayAuction rngRelayAuction = env.rngRelayAuction();

    uint32 lastSequenceId = rngAuction.lastSequenceId();

    if (rngAuction.isAuctionOpen()) {
      UD2x18 rewardFraction = rngAuction.currentFractionalReward();

      AuctionResult memory auctionResult = AuctionResult({
        rewardFraction: rewardFraction,
        recipient: address(this)
      });

      AuctionResult[] memory auctionResults = new AuctionResult[](1);
      auctionResults[0] = auctionResult;

      uint256[] memory rewards = rngRelayAuction.computeRewards(auctionResults);

      if (rewards[0] > minimumAwardingProfit) {
        rngAuction.startRngRequest(address(this));
        // uint256 profit = rewards[0] - minimumAwardingProfit;
        // uint256 delay = block.timestamp -
        //   env.prizePool().drawClosesAt(env.prizePool().getDrawIdToAward());
        // console2.log("RngAuction !!!!!!!!!!!!!! time after draw end:", delay);
      } else {
        // console2.log("RngAuction does not meet minimumAwardingProfit", rewards[0], minimumAwardingProfit);
      }
    }

    // console2.log("rngAuction.lastSequenceId(): ", rngAuction.lastSequenceId());
    // if (rngAuction.lastSequenceId() > 0) {
    //   console2.log("rngAuction.isRngComplete():", rngAuction.isRngComplete());
    //   console2.log("rngRelayAuction.isSequenceCompleted(lastSequenceId): ", rngRelayAuction.isSequenceCompleted(lastSequenceId));
    // }

    if (
      lastSequenceId > 0 && // if there is a last sequence id
      rngAuction.isRngComplete() && // and it's ready
      !rngRelayAuction.isSequenceCompleted(lastSequenceId)
    ) {
      // if the last sequence is not completed

      (, /* uint256 randomNumber */ uint64 completedAt) = rngAuction.getRngResults();

      // compute reward
      AuctionResult memory rngAuctionResult = rngAuction.getLastAuctionResult();

      uint64 elapsedTime = uint64(block.timestamp - completedAt);
      // console2.log("lastSequenceId", lastSequenceId);
      // console2.log("env.prizePool().lastClosedDrawId()", env.prizePool().getLastAwardedDrawId());
      // console2.log("env.prizePool().drawClosesAt(prizePool.getDrawIdToAward())()", env.prizePool().drawClosesAt(prizePool.getDrawIdToAward())());
      // console2.log("completedAt", completedAt);
      // console2.log("block.timestamp", block.timestamp);

      UD2x18 rewardFraction = rngRelayAuction.computeRewardFraction(elapsedTime);

      AuctionResult memory auctionResult = AuctionResult({
        rewardFraction: rewardFraction,
        recipient: address(this)
      });

      AuctionResult[] memory auctionResults = new AuctionResult[](2);
      auctionResults[0] = rngAuctionResult;
      auctionResults[1] = auctionResult;

      uint256[] memory rewards = rngRelayAuction.computeRewards(auctionResults);

      uint256 profit = rewards[1] > minimumRelayProfit ? rewards[1] - minimumRelayProfit : 0;

      if (profit > totalCost) {
        uint256 sinceClosed;
        if (env.prizePool().getLastAwardedDrawId() != 0) {
          sinceClosed =
            block.timestamp -
            env.prizePool().drawClosesAt(env.prizePool().getDrawIdToAward());
        }
        // uint delay = block.timestamp - env.prizePool().drawClosesAt(prizePool.getDrawIdToAward())();
        // uint profit = rewards[1] - minimumProfit;
        drawCount++;

        rngAuctionRelayerRemoteOwner.relay(
          messageDispatcherOptimism,
          10,
          remoteOwner,
          remoteRngAuctionRelayListener,
          address(this),
          250_000
        );

        console2.log(
          "RngRelayAuction -----------> current draw id %s, time since last draw ended:",
          env.prizePool().getLastAwardedDrawId(),
          sinceClosed
        );
      } else {
        // console2.log("RngRelayAuction does not meet minimumProfit", rewards[1], minimumProfit);
      }
    }
  }

  function getMinimumProfit(uint256 _cost) public pure returns (uint256) {
    return _cost + (_cost / 10); // require 10% profit
  }
}
