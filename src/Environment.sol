// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
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

import { YieldVaultMintRate } from "./YieldVaultMintRate.sol";

import { Constants } from "./utils/Constants.sol";

struct PrizePoolConfig {
  uint24 grandPrizePeriodDraws;
  uint32 drawPeriodSeconds;
  uint48 firstDrawOpensAt;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 reserveShares;
  SD1x18 smoothing;
}

struct CgdaLiquidatorConfig {
  SD59x18 decayConstant;
  SD59x18 exchangeRatePrizeTokenToUnderlying;
  uint32 periodLength;
  uint32 periodOffset;
  uint32 targetFirstSaleTime;
}

struct DaLiquidatorConfig {
  SD59x18 initialTargetExchangeRate;
  SD59x18 phaseTwoDurationPercent;
  SD59x18 phaseTwoRangePercent;
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

// @TODO: Ideally, we should have an Ethereum and Optimism environment
// and configurations should only live in this file, not in the tests
contract Environment is Constants, CommonBase, StdCheats {
  ERC20PermitMock public prizeToken;
  ERC20PermitMock public underlyingToken;
  TwabController public twab;
  VaultFactory public vaultFactory;
  Vault public vault;
  YieldVaultMintRate public yieldVault;
  ILiquidationPair public pair;
  PrizePool public prizePool;
  Claimer public claimer;
  LiquidationRouter public router;
  RNGInterface public rng;
  RngAuction public rngAuction;
  RngAuctionRelayerDirect public rngAuctionRelayerDirect;
  RngRelayAuction public rngRelayAuction;

  address[] public users;

  function initialize(
    PrizePoolConfig memory _prizePoolConfig,
    ClaimerConfig memory _claimerConfig,
    RngAuctionConfig memory _rngAuctionConfig
  ) public {
    rng = new RNGBlockhash();
    rngAuction = new RngAuction(
      rng,
      address(this),
      _prizePoolConfig.drawPeriodSeconds,
      _rngAuctionConfig.sequenceOffset,
      _rngAuctionConfig.auctionDuration,
      _rngAuctionConfig.auctionTargetTime,
      _rngAuctionConfig.firstAuctionTargetRewardFraction
    );

    rngAuctionRelayerDirect = new RngAuctionRelayerDirect(rngAuction);
    prizeToken = new ERC20PermitMock("POOL");
    underlyingToken = new ERC20PermitMock("USDC");
    yieldVault = new YieldVaultMintRate(underlyingToken, "Yearnish yUSDC", "yUSDC", address(this));
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

    rngRelayAuction = new RngRelayAuction(
      prizePool,
      _rngAuctionConfig.auctionDuration,
      _rngAuctionConfig.auctionTargetTime,
      address(rngAuctionRelayerDirect),
      _getFirstRngRelayAuctionTargetRewardFraction(),
      AUCTION_MAX_REWARD
    );

    vaultFactory = new VaultFactory();

    claimer = new Claimer(
      prizePool,
      _claimerConfig.minimumFee,
      _claimerConfig.maximumFee,
      _claimerConfig.timeToReachMaxFee,
      _claimerConfig.maxFeePortionOfPrize
    );

    prizePool.setDrawManager(address(rngRelayAuction));

    vault = Vault(
      vaultFactory.deployVault(
        underlyingToken,
        "PoolTogether Prize USDC",
        "pzUSDC",
        yieldVault,
        prizePool,
        address(claimer),
        address(0),
        0,
        address(this)
      )
    );
  }

  function initializeCgdaLiquidator(
    CgdaLiquidatorConfig memory _liquidatorConfig
  ) external virtual {
    LiquidationPairFactory pairFactory = new LiquidationPairFactory();
    LiquidationRouter cgdaRouter = new LiquidationRouter(pairFactory);

    // console2.log(
    //   "initializeCgdaLiquidator _liquidatorConfig.exchangeRatePrizeTokenToUnderlying",
    //   _liquidatorConfig.exchangeRatePrizeTokenToUnderlying.unwrap()
    // );

    uint104 _initialAmountIn = 1e18; // 1 POOL
    uint104 _initialAmountOut = uint104(
      uint256(
        convert(
          convert(int256(uint256(_initialAmountIn))).div(
            _liquidatorConfig.exchangeRatePrizeTokenToUnderlying
          )
        )
      )
    );

    // console2.log("initializeCgdaLiquidator _initialAmountIn", _initialAmountIn);
    // console2.log("initializeCgdaLiquidator _initialAmountOut", _initialAmountOut);

    pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(vault)),
          address(prizeToken),
          address(vault),
          _liquidatorConfig.periodLength,
          _liquidatorConfig.periodOffset,
          _liquidatorConfig.targetFirstSaleTime,
          _liquidatorConfig.decayConstant,
          _initialAmountIn,
          _initialAmountOut,
          1e18
        )
      )
    );
    // force the cast
    router = LiquidationRouter(address(cgdaRouter));
    vault.setLiquidationPair(address(pair));
  }

  function addUsers(uint256 count, uint256 depositSize) external {
    for (uint256 i = 0; i < count; i++) {
      address user = makeAddr(string.concat("user", string(abi.encode(i))));
      vm.startPrank(user);
      underlyingToken.mint(user, depositSize);
      underlyingToken.approve(address(vault), depositSize);
      vault.deposit(depositSize, user);
      vm.stopPrank();
      users.push(user);
    }
  }

  function userCount() external view returns (uint256) {
    return users.length;
  }

  function mintYield() external {
    yieldVault.mintRate();
  }

  function setApr(uint256 fixedPoint18) external {
    uint256 ratePerSecond = fixedPoint18 / 365 days;
    yieldVault.setRatePerSecond(ratePerSecond);
  }
}
