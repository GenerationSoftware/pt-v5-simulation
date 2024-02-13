// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { StdCheats } from "forge-std/StdCheats.sol";

import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";

import { RNGBlockhash } from "rng/RNGBlockhash.sol";
import { RNGInterface } from "rng/RNGInterface.sol";
import { RngAuction } from "pt-v5-draw-auction/RngAuction.sol";
import { RngAuctionRelayerDirect } from "pt-v5-draw-auction/RngAuctionRelayerDirect.sol";
import { RngRelayAuction } from "pt-v5-draw-auction/RngRelayAuction.sol";

import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams } from "pt-v5-prize-pool/PrizePool.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";
import { Utils } from "../utils/Utils.sol";

contract BaseEnvironment is Config, Constant, Utils, StdCheats {
  ERC20PermitMock public prizeToken;
  PrizePool public prizePool;
  RNGInterface public rng;
  RngAuction public rngAuction;
  RngAuctionRelayerDirect public rngAuctionRelayerDirect;
  RngRelayAuction public rngRelayAuction;
  TwabController public twab;

  constructor(PrizePoolConfig memory _prizePoolConfig, RngAuctionConfig memory _rngAuctionConfig) {
    twab = new TwabController(
      _prizePoolConfig.drawPeriodSeconds,
      _getTwabControllerOffset(_prizePoolConfig)
    );

    prizeToken = new ERC20PermitMock("WETH");

    prizePool = new PrizePool(
      ConstructorParams({
        prizeToken: prizeToken,
        twabController: twab,
        drawPeriodSeconds: _prizePoolConfig.drawPeriodSeconds,
        firstDrawOpensAt: _prizePoolConfig.firstDrawOpensAt,
        grandPrizePeriodDraws: _prizePoolConfig.grandPrizePeriodDraws,
        numberOfTiers: _prizePoolConfig.numberOfTiers,
        tierShares: _prizePoolConfig.tierShares,
        reserveShares: _prizePoolConfig.reserveShares,
        drawTimeout: _prizePoolConfig.drawTimeout
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

    prizePool.setDrawManager(address(rngRelayAuction));
  }
}
