// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { CommonBase } from "forge-std/Base.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { SD59x18OverTime } from "./SD59x18OverTime.sol";
import { UintOverTime } from "./UintOverTime.sol";

struct SimulationConfig {
  uint256 durationDraws;
  uint256 numUsers;
  uint256 timeStep;
  uint256 totalValueLocked;
  uint256 verbosity;
  uint256 gpBoost;
  uint256 gpBoostPerDraw;
  uint256 gpBoostPerDrawLastDraw;
}

// Contracts configs
struct PrizePoolConfig {
  uint24 drawTimeout;
  uint24 grandPrizePeriodDraws;
  uint256 tierLiquidityUtilizationRate;
  uint32 drawPeriodSeconds;
  uint48 firstDrawOpensAt;
  uint8 canaryShares;
  uint8 numberOfTiers;
  uint8 reserveShares;
  uint8 tierShares;
}

struct LiquidatorConfig {
  uint64 liquidationPairSearchDensity;
}

struct ClaimerConfig {
  uint256 timeToReachMaxFee;
  UD2x18 maxFeePortionOfPrize;
}

struct DrawManagerConfig {
  uint48 sequenceOffset;
  uint48 auctionDuration;
  uint48 auctionTargetTime;
  uint256 auctionMaxReward;
  UD2x18 firstAuctionTargetRewardFraction;
}

// Gas configs
struct GasConfig {
  uint256 startDrawCostInUsd;
  uint256 finishDrawCostInUsd;
  uint256 claimCostInUsd;
  uint256 liquidationCostInUsd;
}

uint constant USD_DECIMALS = 3;

contract Config is CommonBase {
  using SafeCast for uint256;

  UintOverTime public aprOverTime;
  UintOverTime public tvlOverTime;

  SD59x18OverTime public wethUsdValueOverTime; // Value of WETH over time (USD / WETH)
  SD59x18OverTime public poolUsdValueOverTime; // Value of the pool token over time (USD / POOL)

  SimulationConfig      internal _simulation;
  PrizePoolConfig       internal _prizePool;
  LiquidatorConfig      internal _liquidator;
  ClaimerConfig         internal _claimer;
  DrawManagerConfig     internal _drawManager;
  GasConfig             internal _gas;

  function simulation() public view returns (SimulationConfig memory) { return _simulation; }
  function prizePool() public view returns (PrizePoolConfig memory) { return _prizePool; }
  function liquidator() public view returns (LiquidatorConfig memory) { return _liquidator; }
  function claimer() public view returns (ClaimerConfig memory) { return _claimer; }
  function drawManager() public view returns (DrawManagerConfig memory) { return _drawManager; }
  function gas() public view returns (GasConfig memory) { return _gas; }

  function load(string memory filepath) public {
    string memory config = vm.readFile(filepath);

    poolUsdValueOverTime = new SD59x18OverTime();
    poolUsdValueOverTime.add(block.timestamp, convert(int(10**USD_DECIMALS)).div(convert(1e18))); // USD / POOL

    _simulation.numUsers = vm.parseJsonUint(config, "$.simulation.num_users");
    _simulation.timeStep = vm.parseJsonUint(config, "$.simulation.time_step");
    _simulation.totalValueLocked = uint(convert(convert(int(vm.parseJsonUint(config, "$.simulation.tvl_usd"))).mul(convert(int(10**USD_DECIMALS))).div(poolUsdValueOverTime.get(block.timestamp))));
    _simulation.verbosity = vm.parseJsonUint(config, "$.simulation.verbosity");
    _simulation.durationDraws = vm.parseJsonUint(config, "$.simulation.duration_draws");
    _simulation.gpBoost = vm.parseJsonUint(config, "$.simulation.gp_boost");
    _simulation.gpBoostPerDraw = vm.parseJsonUint(config, "$.simulation.gp_boost_per_draw");
    _simulation.gpBoostPerDrawLastDraw = vm.parseJsonUint(config, "$.simulation.gp_boost_per_draw_last_draw");
    
    _prizePool.drawPeriodSeconds = vm.parseJsonUint(config, "$.prize_pool.draw_period_seconds").toUint32();
    _prizePool.firstDrawOpensAt = uint48(block.timestamp + _prizePool.drawPeriodSeconds);
    _prizePool.grandPrizePeriodDraws = vm.parseJsonUint(config, "$.prize_pool.grand_prize_period_draws").toUint24();
    _prizePool.numberOfTiers = vm.parseJsonUint(config, "$.prize_pool.number_of_tiers").toUint8();
    _prizePool.reserveShares = vm.parseJsonUint(config, "$.prize_pool.reserve_shares").toUint8();
    _prizePool.canaryShares = vm.parseJsonUint(config, "$.prize_pool.canary_shares").toUint8();
    _prizePool.tierShares = vm.parseJsonUint(config, "$.prize_pool.tier_shares").toUint8();
    _prizePool.drawTimeout = vm.parseJsonUint(config, "$.prize_pool.draw_timeout").toUint24();
    _prizePool.tierLiquidityUtilizationRate = vm.parseJsonUint(config, "$.prize_pool.tier_liquidity_utilization_rate");

    _drawManager.auctionDuration = vm.parseJsonUint(config, "$.draw_manager.auction_duration").toUint48();
    _drawManager.auctionTargetTime = vm.parseJsonUint(config, "$.draw_manager.auction_target_time").toUint48();
    _drawManager.auctionMaxReward = vm.parseJsonUint(config, "$.draw_manager.auction_max_reward");
    _drawManager.firstAuctionTargetRewardFraction = ud2x18(vm.parseJsonUint(config, "$.draw_manager.first_auction_target_reward_fraction").toUint64());
    
    _liquidator.liquidationPairSearchDensity = vm.parseJsonUint(config, "$.liquidator.liquidation_pair_search_density").toUint64();    

    _claimer.timeToReachMaxFee = getClaimerTimeToReachMaxFee();
    _claimer.maxFeePortionOfPrize = getClaimerMaxFeePortionOfPrize();

    _gas.startDrawCostInUsd = vm.parseJsonUint(config, "$.gas.start_draw_cost_in_usd"); 
    _gas.finishDrawCostInUsd = vm.parseJsonUint(config, "$.gas.award_draw_cost_in_usd"); 
    _gas.claimCostInUsd = vm.parseJsonUint(config, "$.gas.claim_cost_in_usd"); 
    _gas.liquidationCostInUsd = vm.parseJsonUint(config, "$.gas.liquidation_cost_in_usd"); 

    wethUsdValueOverTime = new SD59x18OverTime();
    uint[] memory ethPrices = vm.parseJsonUintArray(config, "$.simulation.eth_price_usd_per_draw");
    if (ethPrices.length > 0) {
      for (uint i = 0; i < ethPrices.length; i++) {
        wethUsdValueOverTime.add(
          block.timestamp + (i * _prizePool.drawPeriodSeconds),
          convert(int(ethPrices[i] * 10**USD_DECIMALS)).div(convert(1e18))
        );
      }
    }

    aprOverTime = new UintOverTime();
    uint[] memory aprs = vm.parseJsonUintArray(config, "$.simulation.apr_for_each_draw");
    if (aprs.length > 0) {
      for (uint i = 0; i < aprs.length; i++) {
        aprOverTime.add(block.timestamp + (i * _prizePool.drawPeriodSeconds), aprs[i]);
      }
    }

  }

  /// @notice Convert USD to WETH.  NOTE: USD must be fixed point USD decimals
  /// @dev see USD_DECIMALS above
  function usdToWeth(uint usdFixedPointDecimals) public view returns (uint256) {
    return uint256(convert(convert(int(usdFixedPointDecimals)).div(wethUsdValueOverTime.get(block.timestamp))));
  }

  /**
   * @notice Get Liquidation Pair decay constant.
   * @dev This is approximately the maximum decay constant, as the CGDA formula requires computing e^(decayConstant * time).
   *      Since the data type is SD59x18 and e^134 ~= 1e58, we can divide 134 by the draw period to get the max decay constant.
   */
  function getDecayConstant() public view returns (SD59x18) {
    return SD59x18.wrap(134e18).div(convert(int256(uint256(_drawManager.auctionDuration * 50))));
  }

  function getTargetFirstSaleTime() public view returns (uint32) {
    return _prizePool.drawPeriodSeconds / 2;
  }

  // Claimer
  function getClaimerTimeToReachMaxFee() public view returns (uint256) {
    // console2.log("getClaimerTimeToReachMaxFee _prizePool.drawPeriodSeconds: ", _prizePool.drawPeriodSeconds);
    // console2.log("getClaimerTimeToReachMaxFee _drawManager.auctionDuration: ", _drawManager.auctionDuration);
    return (_prizePool.drawPeriodSeconds - (2 * _drawManager.auctionDuration)) / 2;
  }

  function getClaimerMaxFeePortionOfPrize() public view returns (UD2x18) {
    return ud2x18(0.5e18);
  }

  function getFirstDrawOpensAt(uint256 _startTime) public view returns (uint48) {
    return uint48(_startTime + _prizePool.drawPeriodSeconds);
  }

  // RngAuctions
  function getFirstRngRelayAuctionTargetRewardFraction() public view returns (UD2x18) {
    return ud2x18(0);
  }

  function getRngAuctionSequenceOffset(uint64 _firstDrawOpensAt) public view returns (uint64) {
    return _firstDrawOpensAt;
  }

  // TwabController
  function getTwabControllerOffset() public view returns (uint32) {
    return uint32(_prizePool.firstDrawOpensAt - _prizePool.drawPeriodSeconds * 10); // set into the past
  }
  
}
