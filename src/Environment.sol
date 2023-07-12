// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Vault } from "v5-vault/Vault.sol";
import { VaultFactory } from "v5-vault/VaultFactory.sol";
import { ERC20PermitMock } from "v5-vault-test/contracts/mock/ERC20PermitMock.sol";
import { DrawAuction } from "v5-draw-beacon/DrawAuction.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";
import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { LiquidationPair } from "v5-liquidator/LiquidationPair.sol";
import { LiquidationPairFactory } from "v5-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter } from "v5-liquidator/LiquidationRouter.sol";
import { UFixed32x4 } from "v5-liquidator/libraries/FixedMathLib.sol";
import { PrizePool, ConstructorParams } from "v5-prize-pool/PrizePool.sol";
import { Claimer } from "v5-vrgda-claimer/Claimer.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { ILiquidationSource as CgdaILiquidationSource } from "v5-cgda-liquidator/interfaces/ILiquidationSource.sol";
import { LiquidationPair as CgdaLiquidationPair } from "v5-cgda-liquidator/LiquidationPair.sol";
import { LiquidationPairFactory as CgdaLiquidationPairFactory } from "v5-cgda-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter as CgdaLiquidationRouter } from "v5-cgda-liquidator/LiquidationRouter.sol";

import { YieldVaultMintRate } from "src/YieldVaultMintRate.sol";

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
}

struct LiquidatorConfig {
  UFixed32x4 swapMultiplier;
  UFixed32x4 liquidityFraction;
  uint128 virtualReserveIn;
  uint128 virtualReserveOut;
  uint256 mink;
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
  LiquidationPair public pair;
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

  function initializeVmmLiquidator(LiquidatorConfig memory _liquidatorConfig) external virtual {
    LiquidationPairFactory pairFactory = new LiquidationPairFactory();
    router = new LiquidationRouter(pairFactory);
    pair = pairFactory.createPair(
      ILiquidationSource(address(vault)),
      address(prizeToken),
      address(vault),
      _liquidatorConfig.swapMultiplier,
      _liquidatorConfig.liquidityFraction,
      _liquidatorConfig.virtualReserveIn,
      _liquidatorConfig.virtualReserveOut,
      _liquidatorConfig.mink
    );
    vault.setLiquidationPair(pair);
  }

  function initializeCgdaLiquidator(CgdaLiquidatorConfig memory _liquidatorConfig) external virtual {
    CgdaLiquidationPairFactory pairFactory = new CgdaLiquidationPairFactory();
    CgdaLiquidationRouter cgdaRouter = new CgdaLiquidationRouter(pairFactory);
    
    console2.log("initializeCgdaLiquidator _liquidatorConfig.exchangeRatePrizeTokenToUnderlying", _liquidatorConfig.exchangeRatePrizeTokenToUnderlying.unwrap());

    uint112 _initialAmountIn = 1e18; // 1 POOL
    uint112 _initialAmountOut = uint112(uint(convert(convert(int(uint(_initialAmountIn))).div(_liquidatorConfig.exchangeRatePrizeTokenToUnderlying))));

    console2.log("initializeCgdaLiquidator _initialAmountIn", _initialAmountIn);
    console2.log("initializeCgdaLiquidator _initialAmountOut", _initialAmountOut);

    pair = LiquidationPair(address(pairFactory.createPair(
      CgdaILiquidationSource(address(vault)),
      address(prizeToken),
      address(vault),
      _liquidatorConfig.periodLength,
      _liquidatorConfig.periodOffset,
      _liquidatorConfig.periodLength / 8, // 24th of length
      _liquidatorConfig.decayConstant,
      _initialAmountIn,
      _initialAmountOut
    )));
    // force the cast
    router = LiquidationRouter(address(cgdaRouter));
    vault.setLiquidationPair(pair);
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
