// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SafeCast } from "openzeppelin/utils/math/SafeCast.sol";

import { SD59x18OverTime } from "./SD59x18OverTime.sol";
import { UintOverTime } from "./UintOverTime.sol";

struct SimulationConfig {
  uint256 durationDraws;
  uint256 numUsers;
  uint256 simpleApr;
  uint256 timeStep;
  uint256 totalValueLocked;
  uint256 verbosity;
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
  uint256 minimumFee;
  uint256 maximumFee;
  uint256 timeToReachMaxFee;
  UD2x18 maxFeePortionOfPrize;
}

struct DrawManagerConfig {
  uint64 sequenceOffset;
  uint64 auctionDuration;
  uint64 auctionTargetTime;
  uint256 auctionMaxReward;
  UD2x18 firstAuctionTargetRewardFraction;
}

// Gas configs
struct GasConfig {
  uint256 startDrawCostInEth;
  uint256 awardDrawCostInEth;
  uint256 claimCostInEth;
  uint256 liquidationCostInEth;
}

contract Config is CommonBase {
  using SafeCast for uint256;

  UintOverTime public aprOverTime;

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

    wethUsdValueOverTime = new SD59x18OverTime();
    wethUsdValueOverTime.add(block.timestamp, convert(3000e2).div(convert(1e18))); // USD / WETH

    poolUsdValueOverTime = new SD59x18OverTime();
    poolUsdValueOverTime.add(block.timestamp, convert(1e2).div(convert(1e18))); // USD / POOL

    _simulation.numUsers = vm.parseJsonUint(config, "$.simulation.num_users");
    _simulation.timeStep = vm.parseJsonUint(config, "$.simulation.time_step");
    _simulation.simpleApr = vm.parseJsonUint(config, "$.simulation.simple_apr");
    _simulation.totalValueLocked = uint(convert(convert(int(vm.parseJsonUint(config, "$.simulation.tvl_usd"))).div(poolUsdValueOverTime.get(block.timestamp))));
    _simulation.verbosity = vm.parseJsonUint(config, "$.simulation.verbosity");
    _simulation.durationDraws = vm.parseJsonUint(config, "$.simulation.duration_draws");
    
    _prizePool.drawPeriodSeconds = vm.parseJsonUint(config, "$.prize_pool.draw_period_seconds").toUint32();
    _prizePool.firstDrawOpensAt = uint48(block.timestamp + _prizePool.drawPeriodSeconds);
    _prizePool.grandPrizePeriodDraws = vm.parseJsonUint(config, "$.prize_pool.grand_prize_period_draws").toUint24();
    _prizePool.numberOfTiers = vm.parseJsonUint(config, "$.prize_pool.number_of_tiers").toUint8();
    _prizePool.reserveShares = vm.parseJsonUint(config, "$.prize_pool.reserve_shares").toUint8();
    _prizePool.canaryShares = vm.parseJsonUint(config, "$.prize_pool.canary_shares").toUint8();
    _prizePool.tierShares = vm.parseJsonUint(config, "$.prize_pool.tier_shares").toUint8();
    _prizePool.drawTimeout = vm.parseJsonUint(config, "$.prize_pool.draw_timeout").toUint24();
    _prizePool.tierLiquidityUtilizationRate = vm.parseJsonUint(config, "$.prize_pool.tier_liquidity_utilization_rate");
    
    _drawManager.auctionDuration = vm.parseJsonUint(config, "$.draw_manager.auction_duration").toUint64();
    _drawManager.auctionTargetTime = vm.parseJsonUint(config, "$.draw_manager.auction_target_time").toUint64();
    _drawManager.auctionMaxReward = vm.parseJsonUint(config, "$.draw_manager.auction_max_reward");
    _drawManager.firstAuctionTargetRewardFraction = ud2x18(vm.parseJsonUint(config, "$.draw_manager.first_auction_target_reward_fraction").toUint64());
    
    _liquidator.liquidationPairSearchDensity = vm.parseJsonUint(config, "$.liquidator.liquidation_pair_search_density").toUint64();    

    _claimer.minimumFee = vm.parseJsonUint(config, "$.claimer.claimer_min_fee");
    _claimer.maximumFee = vm.parseJsonUint(config, "$.claimer.claimer_max_fee");
    _claimer.timeToReachMaxFee = getClaimerTimeToReachMaxFee();
    _claimer.maxFeePortionOfPrize = getClaimerMaxFeePortionOfPrize();

    _gas.startDrawCostInEth = vm.parseJsonUint(config, "$.gas.start_draw_cost_in_eth"); 
    _gas.awardDrawCostInEth = vm.parseJsonUint(config, "$.gas.award_draw_cost_in_eth"); 
    _gas.claimCostInEth = vm.parseJsonUint(config, "$.gas.claim_cost_in_eth"); 
    _gas.liquidationCostInEth = vm.parseJsonUint(config, "$.gas.liquidation_cost_in_eth"); 

    aprOverTime = new UintOverTime();
    aprOverTime.add(block.timestamp, _simulation.simpleApr);
  }

  function setUpAprFromJson(uint256 _startTime) public {
    // aprOverTime = new UintOverTime();

    // string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicAaveApr.json");
    // string memory jsonData = vm.readFile(jsonFile);

    // // NOTE: Options for APR are: .usd or .eth
    // bytes memory usdData = vm.parseJson(jsonData, "$.usd");
    // HistoricApr[] memory aprData = abi.decode(usdData, (HistoricApr[]));

    // uint256 initialTimestamp = aprData[0].timestamp;
    // for (uint256 i = 0; i < aprData.length; i++) {
    //   HistoricApr memory rowData = aprData[i];
    //   aprOverTime.add(_startTime + (rowData.timestamp - initialTimestamp), rowData.apr);
    // }
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
