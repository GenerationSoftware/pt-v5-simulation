// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";

import { Vault } from "pt-v5-vault/Vault.sol";
import { VaultFactory } from "pt-v5-vault/VaultFactory.sol";
import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";

import { RNGBlockhash } from "rng/RNGBlockhash.sol";
import { RNGInterface } from "rng/RNGInterface.sol";
import { RngAuction } from "pt-v5-draw-auction/RngAuction.sol";
import { RngAuctionRelayerDirect } from "pt-v5-draw-auction/RngAuctionRelayerDirect.sol";
import { RngRelayAuction } from "pt-v5-draw-auction/RngRelayAuction.sol";

import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams } from "pt-v5-prize-pool/PrizePool.sol";
import { Claimer } from "pt-v5-claimer/Claimer.sol";

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidationPair } from "pt-v5-cgda-liquidator/LiquidationPair.sol";
import { LiquidationPairFactory } from "pt-v5-cgda-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter } from "pt-v5-cgda-liquidator/LiquidationRouter.sol";

import { YieldVaultMintRate } from "../YieldVaultMintRate.sol";

import { BaseEnvironment } from "../environment/Base.sol";

struct RngAuctionConfig {
  uint64 sequenceOffset;
  uint64 auctionDuration;
  uint64 auctionTargetTime;
  UD2x18 firstAuctionTargetRewardFraction;
}

// @TODO: Ideally, we should have an Ethereum and Optimism EthereumEnvironment
// and configurations should only live in this file, not in the tests
contract EthereumEnvironment is BaseEnvironment {
  ERC20PermitMock public prizeToken;
  PrizePool public prizePool;
  RNGInterface public rng;
  RngAuction public rngAuction;
  RngAuctionRelayerDirect public rngAuctionRelayerDirect;
  RngRelayAuction public rngRelayAuction;
  TwabController public twab;

  function initialize(
    PrizePoolConfig memory _prizePoolConfig,
    RngAuctionConfig memory _rngAuctionConfig
  ) public {
    twab = new TwabController(
      _prizePoolConfig.drawPeriodSeconds,
      uint32(_prizePoolConfig.firstDrawOpensAt - _prizePoolConfig.drawPeriodSeconds * 10) //set into the past
    );

    prizePool = new PrizePool(
      ConstructorParams({
        prizeToken: prizeToken,
        twabController: twab,
        drawPeriodSeconds: _prizePoolConfig.drawPeriodSeconds,
        firstDrawOpensAt: _prizePoolConfig.firstDrawOpensAt,
        smoothing: _prizePoolConfig.smoothing,
        grandPrizePeriodDraws: _prizePoolConfig.grandPrizePeriodDraws,
        numberOfTiers: _prizePoolConfig.numberOfTiers,
        tierShares: _prizePoolConfig.tierShares,
        reserveShares: _prizePoolConfig.reserveShares
      })
    );

    rng = new RNGBlockhash();
    rngAuction = new RngAuction(
      rng,
      address(this),
      DRAW_PERIOD_SECONDS,
      _rngAuctionConfig.sequenceOffset,
      _rngAuctionConfig.auctionDuration,
      _rngAuctionConfig.auctionTargetTime,
      _rngAuctionConfig.firstAuctionTargetRewardFraction
    );

    rngAuctionRelayerDirect = new RngAuctionRelayerDirect(rngAuction);
    rngRelayAuction = new RngRelayAuction(
      prizePool,
      _rngAuctionConfig.auctionDuration,
      _rngAuctionConfig.auctionTargetTime,
      address(rngAuctionRelayerDirect),
      _getFirstRngRelayAuctionTargetRewardFraction(),
      AUCTION_MAX_REWARD
    );

    prizeToken = new ERC20PermitMock("POOL");
  }
}
