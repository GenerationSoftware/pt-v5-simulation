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
      }
    }

    if (rngAuction.isRngComplete() && !rngRelayAuction.isSequenceCompleted(lastSequenceId)) { // then get relay
      (uint randomNumber, uint64 completedAt) = rngAuction.getRngResults();
      
      // compute reward
      AuctionResult memory rngAuctionResult = rngAuction.getLastAuctionResult();

      uint elapsedTime = block.timestamp - completedAt;

      UD2x18 rewardFraction = rngRelayAuction.computeRewardFraction(elapsedTime);

      AuctionResult memory auctionResult = AuctionResult({
        rewardFraction: rewardFraction,
        recipient: address(this)
      });

      AuctionResult[] memory auctionResults = new AuctionResult[](2);
      auctionResults[0] = rngAuctionResult;
      auctionResults[1] = auctionResult;

      uint[] rewards = rngRelayAuction.computeRewards(auctionResults);

      if (rewards[1] > minimum) {
        rngAuctionRelayerDirect.relay(rngRelayAuction, address(this));
      }
    }

  }
}
