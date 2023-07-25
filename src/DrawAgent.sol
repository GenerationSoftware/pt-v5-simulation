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

    // console2.log("PrizePool hasNextDrawFinished: %s", env.prizePool().hasNextDrawFinished());

    if (env.prizePool().hasOpenDrawFinished()) {
      // uint256 lastCompletedDrawStartedAt = env.prizePool().lastClosedDrawStartedAt();
      uint256 nextDrawId = env.prizePool().getOpenDrawId();
      uint256 reserve = env.prizePool().reserve() + env.prizePool().reserveForOpenDraw();

      // console2.log("DrawID: %s", nextDrawId);
      // console2.log("PrizePool reserve: %s", reserve);
      // console2.log("Block Timestamp - last draw start: %s", block.timestamp - lastCompletedDrawStartedAt);

      if (env.rngAuction().isAuctionOpen()) {
        uint256 prizeTokensPerRequest = (25e16 * 135e17) / 1e18; // linkPerReqeust * linkPriceInPrizeTokens / precision
        uint costForRng = gasConfig.gasUsagePerChainlinkRequest * gasConfig.gasPriceInPrizeTokens + prizeTokensPerRequest;
        uint minimumForRng = costForRng + (costForRng / 10); // require 10% profit

        uint256 reward = env.rngAuction().currentRewardAmount(reserve);
        if (reward > 0) {
          console2.log("---------------- DrawAgent predicted RngAuction reward:  %s.%s * cost (%s)", reward / costForRng, ((reward * 100) / costForRng) % 100, reward);
        }
        if (reward >= minimumForRng) {
          console2.log("---------------- DrawAgent RngAuction Completed for Draw: %s", nextDrawId);
          console2.log("---------------- DrawAgent RngAuction Completed after %s minutes.", env.rngAuction().elapsedTime() / 60);
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
        uint costForDraw = (gasConfig.gasUsagePerCompleteDraw + gasConfig.gasUsagePerStartDraw) *
          gasConfig.gasPriceInPrizeTokens;
        uint minimumForDraw = costForDraw + (costForDraw / 10); // require 10% profit

        uint256 reward = env.drawAuction().currentRewardAmount(reserve);
        if (reward > 0) {
          console2.log("---------------- DrawAgent predicted DrawAuction reward: %s.%s * cost (%s)", reward / costForDraw, ((reward * 100) / costForDraw) % 100, reward);
        }
        if (reward >= minimumForDraw) {
          console2.log("---------------- DrawAgent DrawAuction Completed for Draw: %s", nextDrawId);
          console2.log("---------------- DrawAgent DrawAuction Completed after %s minutes.", env.drawAuction().elapsedTime() / 60);
          env.drawAuction().completeDraw(address(this));
          // console2.log("---------------- Total liquidity for draw: ", env.prizePool().getTotalContributionsForCompletedDraw() / 1e18);
          drawCount++;
        } else {
          // console2.log("---------------- Insufficient reward to complete DrawAuction: %s", nextDrawId);
        }
      }
    }
  }
}
