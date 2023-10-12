// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD1x18 } from "prb-math/SD1x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

abstract contract Config {
  // Contracts configs
  struct PrizePoolConfig {
    uint24 grandPrizePeriodDraws;
    uint32 drawPeriodSeconds;
    uint48 firstDrawOpensAt;
    uint8 numberOfTiers;
    uint8 tierShares;
    uint8 reserveShares;
    SD1x18 smoothing;
  }

  struct RngAuctionConfig {
    uint64 sequenceOffset;
    uint64 auctionDuration;
    uint64 auctionTargetTime;
    UD2x18 firstAuctionTargetRewardFraction;
  }

  // Gas configs
  struct EthereumGasConfig {
    uint256 gasPriceInPrizeTokens;
    uint256 gasUsagePerStartDraw;
    uint256 gasUsagePerRelayDraw;
    uint256 rngCostInPrizeTokens;
  }

  struct OptimismGasConfig {
    uint256 gasPriceInPrizeTokens;
    uint256 gasUsagePerClaim;
    uint256 gasUsagePerLiquidation;
  }

  function ethereumGasConfig() public pure returns (EthereumGasConfig memory) {
    // 1 ETH is worth 2975 POOL
    // Gas price is around 12 gwei on average during the past 7 days.
    // 12 * 2975 = 35700 POOL gwei
    // 1 ETH is worth 215 LINK
    // To award the draw, around 1 LINK is needed on average during the past 7 days.
    // 1 LINK is worth 14 POOL
    return
      EthereumGasConfig({
        gasPriceInPrizeTokens: 35_700 gwei,
        gasUsagePerStartDraw: 152_473,
        gasUsagePerRelayDraw: 405_000,
        rngCostInPrizeTokens: 14e18
      });
  }

  function optimismGasConfig() public pure returns (OptimismGasConfig memory) {
    // On Optimism gas is 0.07748510571 gwei on average during the past 7 days.
    // 0.07748510571 * 2975 = 230 POOL gwei
    return
      OptimismGasConfig({
        gasPriceInPrizeTokens: 35_700 gwei,
        gasUsagePerClaim: 150_000,
        gasUsagePerLiquidation: 500_000
      });
  }
}
