// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD1x18 } from "prb-math/SD1x18.sol";
import { SD59x18 } from "prb-math/SD59x18.sol";
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
    uint24 drawTimeout;
  }

  struct CgdaLiquidatorConfig {
    SD59x18 decayConstant;
    SD59x18 exchangeRatePrizeTokenToUnderlying;
    uint32 periodLength;
    uint32 periodOffset;
    uint32 targetFirstSaleTime;
  }

  struct ClaimerConfig {
    uint256 minimumFee;
    uint256 maximumFee;
    uint256 timeToReachMaxFee;
    UD2x18 maxFeePortionOfPrize;
  }

  struct RngAuctionConfig {
    uint64 sequenceOffset;
    uint64 auctionDuration;
    uint64 auctionTargetTime;
    UD2x18 firstAuctionTargetRewardFraction;
  }

  // Gas configs
  struct GasConfig {
    uint256 gasPriceInPrizeTokens;
    uint256 gasUsagePerStartDraw;
    uint256 gasUsagePerRelayDraw;
    uint256 gasUsagePerClaim;
    uint256 gasUsagePerLiquidation;
    uint256 rngCostInPrizeTokens;
  }

}
