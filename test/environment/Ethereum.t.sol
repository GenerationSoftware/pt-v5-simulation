// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";

import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";

import { DrawAgent } from "../../src/agent/Draw.sol";
import { EthereumEnvironment } from "../../src/environment/Ethereum.sol";

import { BaseTest } from "./Base.t.sol";

contract EthereumTest is BaseTest {
  string simulatorCsvFile = string.concat(vm.projectRoot(), "/data/ethereumSimulatorOut.csv");
  string simulatorCsvColumns = "Draw ID, Timestamp, APR, TVL";

  uint256 duration;
  uint256 timeStep = 20 minutes;
  uint256 startTime;
  uint48 firstDrawOpensAt;

  uint256 totalValueLocked;
  uint256 apr = 0.025e18; // 2.5%

  ERC20PermitMock public prizeToken;
  PrizePool public prizePool;

  PrizePoolConfig public prizePoolConfig;
  RngAuctionConfig public rngAuctionConfig;
  EthereumEnvironment public env;

  DrawAgent public drawAgent;

  uint256 verbosity;

  function setUp() public {
    startTime = block.timestamp + 10000 days;
    vm.warp(startTime);

    firstDrawOpensAt = _getFirstDrawOpensAt(startTime);

    totalValueLocked = vm.envUint("TVL") * 1e18;
    console2.log("TVL: ", vm.envUint("TVL"));

    if (totalValueLocked == 0) {
      revert("Please define TVL env var > 0");
    }

    verbosity = vm.envUint("VERBOSITY");
    console2.log("VERBOSITY: ", verbosity);

    // We offset by 2 draw periods cause the first draw opens 1 draw period after start time
    // and one draw period need to pass before we can award it
    duration = vm.envUint("DRAWS") * DRAW_PERIOD_SECONDS + DRAW_PERIOD_SECONDS * 2;
    console2.log("DURATION: ", duration);
    console2.log("DURATION IN DAYS: ", duration / 1 days);

    initOutputFileCsv(simulatorCsvFile, simulatorCsvColumns);

    // setUpExchangeRate(startTime);
    setUpExchangeRateFromJson(startTime);

    // setUpApr(startTime);
    setUpAprFromJson(startTime);

    console2.log("Setting up at timestamp: ", block.timestamp, "day:", block.timestamp / 1 days);
    console2.log("Draw Period (sec): ", DRAW_PERIOD_SECONDS);

    prizePoolConfig = PrizePoolConfig({
      drawPeriodSeconds: DRAW_PERIOD_SECONDS,
      grandPrizePeriodDraws: GRAND_PRIZE_PERIOD_DRAWS,
      firstDrawOpensAt: firstDrawOpensAt,
      numberOfTiers: MIN_NUMBER_OF_TIERS,
      reserveShares: RESERVE_SHARES,
      tierShares: TIER_SHARES,
      smoothing: _getContributionsSmoothing()
    });

    rngAuctionConfig = RngAuctionConfig({
      sequenceOffset: _getRngAuctionSequenceOffset(firstDrawOpensAt),
      auctionDuration: AUCTION_DURATION,
      auctionTargetTime: AUCTION_TARGET_TIME,
      firstAuctionTargetRewardFraction: FIRST_AUCTION_TARGET_REWARD_FRACTION
    });

    env = new EthereumEnvironment(prizePoolConfig, rngAuctionConfig);

    drawAgent = new DrawAgent(env);

    prizeToken = env.prizeToken();
    prizePool = env.prizePool();
  }

  function testEthereum() public noGasMetering recordEvents {
    uint256 previousDrawAuctionSequenceId;

    for (uint256 i = startTime; i <= startTime + duration; i += timeStep) {
      vm.warp(i);
      vm.roll(block.number + 1);

      uint256 contributionAmount = type(uint96).max / (duration / timeStep);

      if (block.timestamp >= firstDrawOpensAt) {
        prizeToken.mint(address(prizePool), contributionAmount);
        prizePool.contributePrizeTokens(makeAddr("vault"), contributionAmount);
      }

      previousDrawAuctionSequenceId = drawAgent.check(previousDrawAuctionSequenceId);

      uint256[] memory logs = new uint256[](4);
      logs[0] = env.prizePool().getLastAwardedDrawId();
      logs[1] = block.timestamp;
      logs[2] = aprOverTime.get(i);
      logs[3] = totalValueLocked;

      logUint256ToCsv(simulatorCsvFile, logs);
    }

    printDraws();
  }

  function printDraws() public view {
    uint256 totalDraws = (block.timestamp - (firstDrawOpensAt + DRAW_PERIOD_SECONDS)) /
      DRAW_PERIOD_SECONDS;
    uint256 missedDraws = (totalDraws) - drawAgent.drawCount();
    console2.log("");
    console2.log("Expected draws", totalDraws);
    console2.log("Actual draws", drawAgent.drawCount());
    console2.log("Missed Draws", missedDraws);
  }
}
