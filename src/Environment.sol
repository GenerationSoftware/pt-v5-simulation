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

struct PrizePoolConfig {
  uint32 grandPrizePeriodDraws;
  uint32 drawPeriodSeconds;
  uint64 firstDrawStartsAt;
  uint8 numberOfTiers;
  uint8 tierShares;
  uint8 canaryShares;
  uint8 reserveShares;
  UD2x18 claimExpansionThreshold;
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

struct GasConfig {
  uint256 gasPriceInPrizeTokens;
  uint256 gasUsagePerClaim;
  uint256 gasUsagePerLiquidation;
  uint256 gasUsagePerStartDraw;
  uint256 gasUsagePerCompleteDraw;
  uint256 gasUsagePerDispatchDraw;
}

contract Environment is CommonBase, StdCheats {
  ERC20PermitMock public prizeToken;
  ERC20PermitMock public underlyingToken;
  TwabController public twab;
  VaultFactory public vaultFactory;
  Vault public vault;
  YieldVaultMintRate public yieldVault;
  ILiquidationPair public pair;
  PrizePool public prizePool;
  Claimer public claimer;
  DrawAuction public drawAuction;
  LiquidationRouter public router;

  address[] public users;

  GasConfig internal _gasConfig;

  function initialize(
    PrizePoolConfig memory _prizePoolConfig,
    ClaimerConfig memory _claimerConfig,
    GasConfig memory gasConfig_
  ) public {
    _gasConfig = gasConfig_;
    prizeToken = new ERC20PermitMock("POOL");
    underlyingToken = new ERC20PermitMock("USDC");
    yieldVault = new YieldVaultMintRate(underlyingToken, "Yearnish yUSDC", "yUSDC", address(this));
    twab = new TwabController(
      _prizePoolConfig.drawPeriodSeconds,
      uint32(_prizePoolConfig.firstDrawStartsAt)
    );

    ConstructorParams memory params = ConstructorParams({
      prizeToken: prizeToken,
      twabController: twab,
      drawManager: address(0),
      //   grandPrizePeriodDraws: _prizePoolConfig.grandPrizePeriodDraws,
      drawPeriodSeconds: _prizePoolConfig.drawPeriodSeconds,
      firstDrawStartsAt: _prizePoolConfig.firstDrawStartsAt,
      numberOfTiers: _prizePoolConfig.numberOfTiers,
      tierShares: _prizePoolConfig.tierShares,
      canaryShares: _prizePoolConfig.canaryShares,
      reserveShares: _prizePoolConfig.reserveShares,
      claimExpansionThreshold: _prizePoolConfig.claimExpansionThreshold,
      smoothing: _prizePoolConfig.smoothing
    });

    prizePool = new PrizePool(params);
    vaultFactory = new VaultFactory();

    claimer = new Claimer(
      prizePool,
      _claimerConfig.minimumFee,
      _claimerConfig.maximumFee,
      _claimerConfig.timeToReachMaxFee,
      _claimerConfig.maxFeePortionOfPrize
    );

    drawAuction = new DrawAuction(prizePool, _prizePoolConfig.drawPeriodSeconds / 8);

    prizePool.setDrawManager(address(drawAuction));

    vault = Vault(
      vaultFactory.deployVault(
        underlyingToken,
        "PoolTogether Prize USDC",
        "pzUSDC",
        twab,
        yieldVault,
        prizePool,
        address(claimer),
        address(0),
        0,
        address(this)
      )
    );
  }

  function initializeDaLiquidator(
    DaLiquidatorConfig memory _liquidatorConfig,
    PrizePoolConfig memory _prizePoolConfig
  ) external virtual {
    LiquidationPairFactory pairFactory = new LiquidationPairFactory(
      _prizePoolConfig.drawPeriodSeconds,
      uint32(_prizePoolConfig.firstDrawStartsAt)
    );
    router = new LiquidationRouter(pairFactory);

    console2.log("~~~ Initialize DaLiquidator ~~~");
    console2.log("Target Exchange Rate", _liquidatorConfig.initialTargetExchangeRate.unwrap());
    console2.log("Phase Two Duration Percent", convert(_liquidatorConfig.phaseTwoDurationPercent));
    console2.log("Phase Two Range Percent", convert(_liquidatorConfig.phaseTwoRangePercent));
    console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

    pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(vault)),
          address(prizeToken),
          address(vault),
          _liquidatorConfig.initialTargetExchangeRate,
          _liquidatorConfig.phaseTwoDurationPercent,
          _liquidatorConfig.phaseTwoRangePercent
        )
      )
    );
    vault.setLiquidationPair(LiquidationPair(address(pair)));
  }

  function initializeCgdaLiquidator(
    CgdaLiquidatorConfig memory _liquidatorConfig
  ) external virtual {
    CgdaLiquidationPairFactory pairFactory = new CgdaLiquidationPairFactory();
    CgdaLiquidationRouter cgdaRouter = new CgdaLiquidationRouter(pairFactory);

    console2.log(
      "initializeCgdaLiquidator _liquidatorConfig.exchangeRatePrizeTokenToUnderlying",
      _liquidatorConfig.exchangeRatePrizeTokenToUnderlying.unwrap()
    );

    uint112 _initialAmountIn = 1e18; // 1 POOL
    uint112 _initialAmountOut = uint112(
      uint(
        convert(
          convert(int(uint(_initialAmountIn))).div(
            _liquidatorConfig.exchangeRatePrizeTokenToUnderlying
          )
        )
      )
    );

    console2.log("initializeCgdaLiquidator _initialAmountIn", _initialAmountIn);
    console2.log("initializeCgdaLiquidator _initialAmountOut", _initialAmountOut);

    pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          CgdaILiquidationSource(address(vault)),
          address(prizeToken),
          address(vault),
          _liquidatorConfig.periodLength,
          _liquidatorConfig.periodOffset,
          _liquidatorConfig.targetFirstSaleTime,
          _liquidatorConfig.decayConstant,
          _initialAmountIn,
          _initialAmountOut
        )
      )
    );
    // force the cast
    router = LiquidationRouter(address(cgdaRouter));
    vault.setLiquidationPair(LiquidationPair(address(pair)));
  }

  function addUsers(uint count, uint depositSize) external {
    for (uint i = 0; i < count; i++) {
      address user = makeAddr(string.concat("user", string(abi.encode(i))));
      vm.startPrank(user);
      underlyingToken.mint(user, depositSize);
      underlyingToken.approve(address(vault), depositSize);
      vault.deposit(depositSize, user);
      vm.stopPrank();
      users.push(user);
    }
  }

  function userCount() external view returns (uint) {
    return users.length;
  }

  function gasConfig() external view returns (GasConfig memory) {
    return _gasConfig;
  }

  function mintYield() external {
    yieldVault.mintRate();
  }

  function setApr(uint fixedPoint18) external {
    uint ratePerSecond = fixedPoint18 / 365 days;
    yieldVault.setRatePerSecond(ratePerSecond);
  }
}
