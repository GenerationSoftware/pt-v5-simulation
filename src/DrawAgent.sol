pragma solidity 0.8.17;

import "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";

import { Environment, GasConfig } from "src/Environment.sol";
import { RewardLib } from "v5-draw-auction/libraries/RewardLib.sol";
import { AuctionResults } from "v5-draw-auction/interfaces/IAuction.sol";

contract DrawAgent {
  Environment public env;
  Vm public vm;

  string drawAgentCsv;

  uint public drawCount;

  DrawAgentLog public drawLog;

  // uint public constant SEED = 0x23423;

  constructor(Environment _env, Vm _vm) {
    env = _env;
    vm = _vm;
    initOutputFileCsv();
  }

  function check() public {
    GasConfig memory gasConfig = env.gasConfig();

    // console2.log("PrizePool hasNextDrawFinished: %s", env.prizePool().hasNextDrawFinished());

    if (env.prizePool().hasOpenDrawFinished()) {
      uint256 lastCompletedDrawStartedAt = env.prizePool().lastClosedDrawStartedAt();
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
          uint decimals = ((reward * 100) / costForRng) % 100;
          console2.log(string.concat(
            "---------------- DrawAgent predicted RngAuction reward:  %s.",
            decimals < 10 ? string.concat("0", vm.toString(decimals)) : vm.toString(decimals),
            " * cost (%se18, %s)"
            ), reward / costForRng, reward / 1e18, reward
          );
        }
        if (reward >= minimumForRng) {
          uint64 fractionalReward = uint64(env.rngAuction().currentFractionalReward().unwrap());

          (AuctionResults memory lastResults,) = env.rngAuction().getAuctionResults();
          drawLog.rngLastFractionalReward = uint64(lastResults.rewardFraction.unwrap());
          drawLog.rngElapsedTime = env.rngAuction().elapsedTime();
          drawLog.rngFractionalReward = fractionalReward;
          drawLog.rngActualReward = reward;
          
          console2.log("---------------- DrawAgent RngAuction Completed for Draw: %s", nextDrawId);
          console2.log("---------------- DrawAgent RngAuction Fractional Cost: %s", fractionalReward);
          console2.log("---------------- DrawAgent RngAuction Completed after %s minutes.", env.rngAuction().elapsedTime() / 60);

          env.rngAuction().startRngRequest(address(this));
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
          uint decimals = ((reward * 100) / costForDraw) % 100;
          console2.log(string.concat(
            "---------------- DrawAgent predicted DrawAuction reward:  %s.",
            decimals < 10 ? string.concat("0", vm.toString(decimals)) : vm.toString(decimals),
            " * cost (%se18, %s)"
            ), reward / costForDraw, reward / 1e18, reward
          );
        }
        if (reward >= minimumForDraw) {
          uint64 fractionalReward = uint64(env.drawAuction().currentFractionalReward().unwrap());

          (AuctionResults memory lastResults,) = env.drawAuction().getAuctionResults();
          drawLog.drawLastFractionalReward = uint64(lastResults.rewardFraction.unwrap());
          drawLog.drawElapsedTime = env.drawAuction().elapsedTime();
          drawLog.drawFractionalReward = fractionalReward;
          drawLog.drawActualReward = reward;

          console2.log("---------------- DrawAgent DrawAuction Completed for Draw: %s", nextDrawId);
          console2.log("---------------- DrawAgent DrawAuction Fractional Cost: %s", uint64(env.drawAuction().currentFractionalReward().unwrap()));
          console2.log("---------------- DrawAgent DrawAuction Completed after %s minutes.", env.drawAuction().elapsedTime() / 60);
          console2.log("---------------- Elapsed Periods: %s", (block.timestamp - lastCompletedDrawStartedAt) / env.prizePool().drawPeriodSeconds() - 1);
          env.drawAuction().completeDraw(address(this));
          // console2.log("---------------- Total liquidity for draw: ", env.prizePool().getTotalContributionsForCompletedDraw() / 1e18);
          drawCount++;

          // LOGS
          drawLog.drawId = nextDrawId;
          drawLog.reserve = reserve;
          logToCsv(drawLog);
          
        } else {
          // console2.log("---------------- Insufficient reward to complete DrawAuction: %s", nextDrawId);
        }
      }
    }
  }

  struct DrawAgentLog {
    uint drawId;
    uint reserve;
    uint rngLastFractionalReward;
    uint rngElapsedTime;
    uint rngFractionalReward;
    uint rngActualReward;
    uint drawLastFractionalReward;
    uint drawElapsedTime;
    uint drawFractionalReward;
    uint drawActualReward;
  }

  // Clears and logs the CSV headers to the file
  function initOutputFileCsv() public {
    drawAgentCsv = string.concat(vm.projectRoot(), "/data/drawAgentOut.csv");
    vm.writeFile(drawAgentCsv, "");
    vm.writeLine(drawAgentCsv, "Draw ID, Reserve, RNG Last Fractional Reward, RNG Elapsed Time, RNG Fractional Reward, RNG Actual Reward, Draw Last Fractional Reward, Draw Elapsed Time, Draw Fractional Reward, Draw Actual Reward");
  }

  // LOGS
  function logToCsv(DrawAgentLog memory log) public {
    vm.writeLine(
      drawAgentCsv,
      string.concat(
        vm.toString(log.drawId),
        ",",
        vm.toString(log.reserve),
        ",",
        vm.toString(log.rngLastFractionalReward),
        ",",
        vm.toString(log.rngElapsedTime),
        ",",
        vm.toString(log.rngFractionalReward),
        ",",
        vm.toString(log.rngActualReward),
        ",",
        vm.toString(log.drawLastFractionalReward),
        ",",
        vm.toString(log.drawElapsedTime),
        ",",
        vm.toString(log.drawFractionalReward),
        ",",
        vm.toString(log.drawActualReward)
      )
    );
  }
}
