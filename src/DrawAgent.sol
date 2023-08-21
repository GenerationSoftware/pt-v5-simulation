pragma solidity 0.8.19;

import "forge-std/console2.sol";

import {
  Environment,
  RngAuction,
  RngAuctionRelayerDirect,
  RngRelayAuction,
  GasConfig
} from "./Environment.sol";

import { UD2x18 } from "prb-math/UD2x18.sol";

import { AuctionResult } from "pt-v5-draw-auction/interfaces/IAuction.sol";

contract DrawAgent {
  Environment public env;

  uint public drawCount;

  uint public constant SEED = 0x23423;

  constructor(Environment _env) {
    env = _env;
  }

  function check() public {
    GasConfig memory gasConfig = env.gasConfig();
    uint cost = (gasConfig.gasUsagePerCompleteDraw + gasConfig.gasUsagePerStartDraw) *
      gasConfig.gasPriceInPrizeTokens;
    uint minimum = cost + (cost / 10); // require 10% profit

    // console2.log("PrizePool hasNextDrawFinished: %s", env.prizePool().hasNextDrawFinished());

    RngAuction rngAuction = env.rngAuction();
    RngAuctionRelayerDirect rngAuctionRelayerDirect = env.rngAuctionRelayerDirect();
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

      if (rewards[0] > minimum) {
        rngAuction.startRngRequest(address(this));
        uint profit = rewards[0] - minimum;
        uint delay = block.timestamp - env.prizePool().openDrawEndsAt();
        // console2.log("RngAuction !!!!!!!!!!!!!! time after draw end:", delay);
      } else {
        // console2.log("RngAuction does not meet minimum", rewards[0], minimum);
      }
    }

    // console2.log("rngAuction.lastSequenceId(): ", rngAuction.lastSequenceId());
    // if (rngAuction.lastSequenceId() > 0) {
    //   console2.log("rngAuction.isRngComplete():", rngAuction.isRngComplete());
    //   console2.log("rngRelayAuction.isSequenceCompleted(lastSequenceId): ", rngRelayAuction.isSequenceCompleted(lastSequenceId));
    // }

    if (lastSequenceId > 0 && // if there is a last sequence id
        rngAuction.isRngComplete() && // and it's ready
        !rngRelayAuction.isSequenceCompleted(lastSequenceId)
    ) { // if the last sequence is not completed

      (uint randomNumber, uint64 completedAt) = rngAuction.getRngResults();
      
      // compute reward
      AuctionResult memory rngAuctionResult = rngAuction.getLastAuctionResult();

      uint64 elapsedTime = uint64(block.timestamp - completedAt);
      // console2.log("lastSequenceId", lastSequenceId);
      // console2.log("env.prizePool().lastClosedDrawId()", env.prizePool().getLastClosedDrawId());
      // console2.log("env.prizePool().openDrawEndsAt()", env.prizePool().openDrawEndsAt());
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

      uint[] memory rewards = rngRelayAuction.computeRewards(auctionResults);

      uint profit = rewards[1] > minimum ? rewards[1] - minimum : 0;

      if (profit > cost) {
        // uint delay = block.timestamp - env.prizePool().openDrawEndsAt();
        // uint profit = rewards[1] - minimum;
        drawCount++;
        rngAuctionRelayerDirect.relay(rngRelayAuction, address(this));
        // console2.log("RngRelayAuction -----------> time after draw end:", delay);
      } else {
        // console2.log("RngRelayAuction does not meet minimum", rewards[1], minimum);
      }
    }

  }
}
