pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment, GasConfig } from "src/Environment.sol";

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

    if (env.prizePool().hasOpenDrawFinished()) {
      uint256 lastCompletedDrawStartedAt = env.prizePool().lastClosedDrawStartedAt();
      uint256 nextDrawId = env.prizePool().getOpenDrawId();
      uint256 reward = env.drawAuction().reward();
      uint256 reserve = env.prizePool().reserve() + env.prizePool().reserveForOpenDraw();

      // console2.log("DrawID: %s", nextDrawId);
      // console2.log("PrizePool reserve: %s", reserve);
      // console2.log("Minimum reward to cover cost: %s", minimum);
      // console2.log("DrawAuction reward: %s", reward);
      // console2.log("Block Timestamp - last draw start: %s", block.timestamp - lastCompletedDrawStartedAt);

      if (reward >= minimum) {
        console2.log("---------------- DrawAgent Draw: %s", nextDrawId);
        // console2.log("---------------- Percentage of the reserve covering DrawAuction reward: %s", reserve > 0 ? reward * 100 / reserve : 0);
        env.drawAuction().completeAndStartNextDraw(
          uint256(keccak256(abi.encodePacked(block.timestamp, SEED)))
        );
        // console2.log("---------------- Total liquidity for draw: ", env.prizePool().getTotalContributionsForCompletedDraw() / 1e18);
        drawCount++;
      } else {
        // console2.log("---------------- Insufficient reward to complete Draw: %s", nextDrawId);
      }
    }
  }
}
