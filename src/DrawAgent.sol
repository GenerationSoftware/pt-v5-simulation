pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment, GasConfig } from "src/Environment.sol";
import { RewardLib } from "v5-draw-auction/libraries/RewardLib.sol";
import { AuctionResults } from "v5-draw-auction/interfaces/IAuction.sol";

contract DrawAgent {
  Environment public env;

  uint public rngCount;
  uint public drawCount;

  // uint public constant SEED = 0x23423;

  constructor(Environment _env) {
    env = _env;
  }

  function check() public {
    GasConfig memory gasConfig = env.gasConfig();

    uint costForRng = (gasConfig.gasUsagePerCompleteDraw + gasConfig.gasUsagePerStartDraw) *
      gasConfig.gasPriceInPrizeTokens;
    uint minimumForRng = costForRng + (costForRng / 10); // require 10% profit

    uint costForDraw = (gasConfig.gasUsagePerCompleteDraw + gasConfig.gasUsagePerStartDraw) *
      gasConfig.gasPriceInPrizeTokens;
    uint minimumForDraw = costForDraw + (costForDraw / 10); // require 10% profit

    // console2.log("PrizePool hasNextDrawFinished: %s", env.prizePool().hasNextDrawFinished());

    if (env.prizePool().hasOpenDrawFinished()) {
      // uint256 lastCompletedDrawStartedAt = env.prizePool().lastClosedDrawStartedAt();
      // uint256 reward = env.drawAuction().reward();
      uint256 nextDrawId = env.prizePool().getOpenDrawId();
      uint256 reserve = env.prizePool().reserve() + env.prizePool().reserveForOpenDraw();

      // console2.log("DrawID: %s", nextDrawId);
      // console2.log("PrizePool reserve: %s", reserve);
      // console2.log("Minimum reward to cover cost: %s", minimum);
      // console2.log("DrawAuction reward: %s", reward);
      // console2.log("Block Timestamp - last draw start: %s", block.timestamp - lastCompletedDrawStartedAt);

      // if (reward >= minimum) {
      //   console2.log("---------------- DrawAgent Draw: %s", nextDrawId);
      //   // console2.log("---------------- Percentage of the reserve covering DrawAuction reward: %s", reserve > 0 ? reward * 100 / reserve : 0);
      //   env.drawAuction().completeAndStartNextDraw(
      //     uint256(keccak256(abi.encodePacked(block.timestamp, SEED)))
      //   );
      //   // console2.log("---------------- Total liquidity for draw: ", env.prizePool().getTotalContributionsForCompletedDraw() / 1e18);
      //   drawCount++;
      // } else {
      //   // console2.log("---------------- Insufficient reward to complete Draw: %s", nextDrawId);
      // }

      if (env.rngAuction().isAuctionOpen()) {
        AuctionResults memory currentResults = AuctionResults(
          address(this),
          env.rngAuction().currentRewardPortion()
        );
        uint256 reward = RewardLib.reward(currentResults, reserve);
        console2.log("---------------- DrawAgent predicted RngAuction reward: %s", reward);
        if (reward >= minimumForRng) {
          console2.log("---------------- DrawAgent RngAuction: %s %s", nextDrawId, block.number);
          env.rngAuction().startRngRequest(address(this));
          rngCount++;
        } else {
          // console2.log("---------------- Insufficient reward to complete RngAuction: %s", nextDrawId);
        }
      } else if (env.rngAuction().isRngComplete()) {
        // finalize random number since we are using the blockhash RNG which needs to be called before it stores the completedAt timestamp
        env.rngAuction().getRngResults();
      }

      if (env.drawAuction().isAuctionOpen()) {
        AuctionResults[] memory currentResults = new AuctionResults[](2);
        (currentResults[0],) = env.rngAuction().getAuctionResults();
        currentResults[1] = AuctionResults(
          address(this),
          env.drawAuction().currentRewardPortion()
        );
        uint256[] memory rewards = RewardLib.rewards(currentResults, reserve);
        console2.log("---------------- DrawAgent predicted DrawAuction reward: %s", rewards[1]);
        if (rewards[1] >= minimumForDraw) {
          console2.log("---------------- DrawAgent DrawAuction: %s", nextDrawId);
          env.drawAuction().completeDraw(address(this));
          drawCount++;
        } else {
          // console2.log("---------------- Insufficient reward to complete DrawAuction: %s", nextDrawId);
        }
      }
    }
  }
}
