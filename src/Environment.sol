// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { UD2x18, intoUD60x18 } from "prb-math/UD2x18.sol";
import { SD1x18, unwrap, UNIT } from "prb-math/SD1x18.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";

import { Vault } from "v5-vault/Vault.sol";
import { VaultFactory } from "v5-vault/VaultFactory.sol";
import { ERC20PermitMock } from "v5-vault-test/contracts/mock/ERC20PermitMock.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams } from "v5-prize-pool/PrizePool.sol";
import { Claimer } from "v5-vrgda-claimer/Claimer.sol";

import { RngAuction } from "v5-draw-auction/RngAuction.sol";
import { DrawManager } from "v5-draw-auction/DrawManager.sol";
import { DrawAuctionDirect } from "v5-draw-auction/DrawAuctionDirect.sol";
import { RNGBlockhash } from "rng-contracts/RNGBlockhash.sol";
import { RNGInterface } from "rng-contracts/RNGInterface.sol"; 

import { ILiquidationSource } from "v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidationPair } from "v5-liquidator/LiquidationPair.sol";
import { LiquidationPairFactory } from "v5-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter } from "v5-liquidator/LiquidationRouter.sol";

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

struct AuctionConfig {
  uint64 auctionDurationSeconds;
  uint64 auctionTargetTime;
}

struct GasConfig {
  uint256 gasPriceInPrizeTokens;
  uint256 gasUsagePerClaim;
  uint256 gasUsagePerLiquidation;
  uint256 gasUsagePerStartDraw;
  uint256 gasUsagePerCompleteDraw;
  uint256 gasUsagePerDispatchDraw;
  uint256 gasUsagePerChainlinkRequest;
}

struct Contracts {
  ERC20PermitMock prizeToken;
  ERC20PermitMock underlyingToken;
  TwabController twab;
  VaultFactory vaultFactory;
  Vault vault;
  YieldVaultMintRate yieldVault;
  ILiquidationPair pair;
  PrizePool prizePool;
  Claimer claimer;
  RNGInterface rng;
  RngAuction rngAuction;
  DrawAuctionDirect drawAuction;
  DrawManager drawManager;
  LiquidationRouter router;
}

contract Environment is CommonBase, StdCheats {
  
  Contracts public contracts;

  address[] public users;

  GasConfig internal _gasConfig;

  bool public outputDataLogs;

  function initialize(
    bool outputDataLogs_,
    PrizePoolConfig memory _prizePoolConfig,
    ClaimerConfig memory _claimerConfig,
    GasConfig memory gasConfig_,
    AuctionConfig memory _rngAuctionConfig,
    AuctionConfig memory _drawAuctionConfig
  ) public {

    outputDataLogs = outputDataLogs_;
    _gasConfig = gasConfig_;

    contracts.prizeToken = new ERC20PermitMock("POOL");
    contracts.underlyingToken = new ERC20PermitMock("USDC");
    contracts.yieldVault = new YieldVaultMintRate(contracts.underlyingToken, "Yearnish yUSDC", "yUSDC", address(this));
    contracts.twab = new TwabController(
      _prizePoolConfig.drawPeriodSeconds,
      uint32(_prizePoolConfig.firstDrawStartsAt)
    );

    ConstructorParams memory params = ConstructorParams({
      prizeToken: contracts.prizeToken,
      twabController: contracts.twab,
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

    contracts.prizePool = new PrizePool(params);
    contracts.vaultFactory = new VaultFactory();
    contracts.claimer = new Claimer(
      contracts.prizePool,
      _claimerConfig.minimumFee,
      _claimerConfig.maximumFee,
      _claimerConfig.timeToReachMaxFee,
      _claimerConfig.maxFeePortionOfPrize
    );

    contracts.rng = new RNGBlockhash();
    contracts.rngAuction = new RngAuction(
      contracts.rng,
      address(this),
      _prizePoolConfig.drawPeriodSeconds,
      _prizePoolConfig.firstDrawStartsAt,
      _rngAuctionConfig.auctionDurationSeconds,
      _rngAuctionConfig.auctionTargetTime
    );
    contracts.drawManager = new DrawManager(contracts.prizePool, address(this), address(0));
    contracts.drawAuction = new DrawAuctionDirect(contracts.drawManager, contracts.rngAuction, _drawAuctionConfig.auctionDurationSeconds, _drawAuctionConfig.auctionTargetTime);
    contracts.drawManager.grantRole(contracts.drawManager.DRAW_CLOSER_ROLE(), address(contracts.drawAuction));
    contracts.prizePool.setDrawManager(address(contracts.drawManager));

    contracts.vault = Vault(
      contracts.vaultFactory.deployVault(
        contracts.underlyingToken,
        "PoolTogether Prize USDC",
        "pzUSDC",
        contracts.twab,
        contracts.yieldVault,
        contracts.prizePool,
        address(contracts.claimer),
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
    contracts.router = new LiquidationRouter(pairFactory);

    console2.log("~~~ Initialize DaLiquidator ~~~");
    console2.log("Target Exchange Rate", _liquidatorConfig.initialTargetExchangeRate.unwrap());
    console2.log("Phase Two Duration Percent", convert(_liquidatorConfig.phaseTwoDurationPercent));
    console2.log("Phase Two Range Percent", convert(_liquidatorConfig.phaseTwoRangePercent));
    console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");

    contracts.pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(contracts.vault)),
          address(contracts.prizeToken),
          address(contracts.vault),
          _liquidatorConfig.initialTargetExchangeRate,
          _liquidatorConfig.phaseTwoDurationPercent,
          _liquidatorConfig.phaseTwoRangePercent
        )
      )
    );
    contracts.vault.setLiquidationPair(LiquidationPair(address(contracts.pair)));
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

    contracts.pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          CgdaILiquidationSource(address(contracts.vault)),
          address(contracts.prizeToken),
          address(contracts.vault),
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
    contracts.router = LiquidationRouter(address(cgdaRouter));
    contracts.vault.setLiquidationPair(LiquidationPair(address(contracts.pair)));
  }

  function addUsers(uint count, uint depositSize) external {
    for (uint i = 0; i < count; i++) {
      address user = makeAddr(string.concat("user", string(abi.encode(i))));
      vm.startPrank(user);
      contracts.underlyingToken.mint(user, depositSize);
      contracts.underlyingToken.approve(address(contracts.vault), depositSize);
      contracts.vault.deposit(depositSize, user);
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
    contracts.yieldVault.mintRate();
  }

  function setApr(uint fixedPoint18) external {
    uint ratePerSecond = fixedPoint18 / 365 days;
    contracts.yieldVault.setRatePerSecond(ratePerSecond);
  }

  // Contract getters
  function prizeToken() public returns (ERC20PermitMock) { return contracts.prizeToken; }
  function underlyingToken() public returns (ERC20PermitMock) { return contracts.underlyingToken; }
  function twab() public returns (TwabController) { return contracts.twab; }
  function vaultFactory() public returns (VaultFactory) { return contracts.vaultFactory; }
  function vault() public returns (Vault) { return contracts.vault; }
  function yieldVault() public returns (YieldVaultMintRate) { return contracts.yieldVault; }
  function pair() public returns (ILiquidationPair) { return contracts.pair; }
  function prizePool() public returns (PrizePool) { return contracts.prizePool; }
  function claimer() public returns (Claimer) { return contracts.claimer; }
  function rng() public returns (RNGInterface) { return contracts.rng; }
  function rngAuction() public returns (RngAuction) { return contracts.rngAuction; }
  function drawAuction() public returns (DrawAuctionDirect) { return contracts.drawAuction; }
  function drawManager() public returns (DrawManager) { return contracts.drawManager; }
  function router() public returns (LiquidationRouter) { return contracts.router; }

}
