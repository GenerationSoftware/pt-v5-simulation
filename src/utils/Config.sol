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
    // Gas price is at 34 gwei
    // It costs about the same gas to start the draw as it does in LINK costs
    uint256 gasPrice = 34 gwei;
    return
      EthereumGasConfig({
        gasPriceInPrizeTokens: gasPrice,
        gasUsagePerStartDraw: 152_473,
        gasUsagePerRelayDraw: 405_000,
        rngCostInPrizeTokens: 152_473 * gasPrice
      });
  }

  function optimismGasConfig() public pure returns (OptimismGasConfig memory) {
    return
      OptimismGasConfig({
        gasPriceInPrizeTokens: 0.3 gwei, // approximating that OP gas is about than 1% mainnet gas
        gasUsagePerClaim: 150_000,
        gasUsagePerLiquidation: 500_000
      });
  }
}
