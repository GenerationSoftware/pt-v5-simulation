// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD1x18, sd1x18 } from "prb-math/SD1x18.sol";
import { UD2x18, ud2x18 } from "prb-math/UD2x18.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";

import { Config } from "./Config.sol";

abstract contract Constant is Config {
  // Claimer
  uint256 internal constant CLAIMER_MIN_FEE = 0.0001e18;
  uint256 internal constant CLAIMER_MAX_FEE = 10000e18;

  // Prize Pool
  // uint32 internal constant DRAW_PERIOD_SECONDS = 1 days;
  uint32 internal constant DRAW_PERIOD_SECONDS = 365 days;
  uint24 internal constant GRAND_PRIZE_PERIOD_DRAWS = 1; // Once a year for daily draws
  uint8 internal constant MIN_NUMBER_OF_TIERS = 3;
  uint8 internal constant RESERVE_SHARES = 100;
  uint8 internal constant TIER_SHARES = 100;

  // RngAuctions
  // uint64 internal constant AUCTION_DURATION = 6 hours;
  uint64 internal constant AUCTION_DURATION = 90 days;
  uint64 internal constant AUCTION_TARGET_TIME = 15 days;
  uint256 internal constant AUCTION_MAX_REWARD = 10000e18;
  UD2x18 internal constant FIRST_AUCTION_TARGET_REWARD_FRACTION = UD2x18.wrap(0.25e18); // 50%

  // CGDA Liquidator

  /**
   * @notice Get Liquidation Pair decay constant.
   * @dev This is approximately the maximum decay constant, as the CGDA formula requires computing e^(decayConstant * time).
   *      Since the data type is SD59x18 and e^134 ~= 1e58, we can divide 134 by the draw period to get the max decay constant.
   */
  function _getDecayConstant() internal pure returns (SD59x18) {
    return SD59x18.wrap(134e18).div(convert(int256(uint256(DRAW_PERIOD_SECONDS * 50))));
  }

  function _getTargetFirstSaleTime() internal pure returns (uint32) {
    return DRAW_PERIOD_SECONDS / 2;
  }

  // Claimer
  function _getClaimerTimeToReachMaxFee() internal pure returns (uint256) {
    return (DRAW_PERIOD_SECONDS - (2 * AUCTION_DURATION)) / 2;
  }

  function _getClaimerMaxFeePortionOfPrize() internal pure returns (UD2x18) {
    return ud2x18(0.5e18);
  }

  // Prize Pool
  function _getContributionsSmoothing() internal pure returns (SD1x18) {
    return sd1x18(0.3e18);
  }

  function _getFirstDrawOpensAt(uint256 _startTime) internal pure returns (uint48) {
    return uint48(_startTime + DRAW_PERIOD_SECONDS);
  }

  // RngAuctions
  function _getFirstRngRelayAuctionTargetRewardFraction() internal pure returns (UD2x18) {
    return ud2x18(0);
  }

  function _getRngAuctionSequenceOffset(uint64 _firstDrawOpensAt) internal pure returns (uint64) {
    return _firstDrawOpensAt;
  }

  // TwabController
  function _getTwabControllerOffset(
    PrizePoolConfig memory _prizePoolConfig
  ) internal pure returns (uint32) {
    return uint32(_prizePoolConfig.firstDrawOpensAt - _prizePoolConfig.drawPeriodSeconds * 10); // set into the past
  }
}
