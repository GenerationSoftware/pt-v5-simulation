// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { StdCheats } from "forge-std/StdCheats.sol";

import { console2 } from "forge-std/console2.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizeVaultFactory } from "pt-v5-vault/PrizeVaultFactory.sol";
import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";
import { RngBlockhash } from "pt-v5-rng-blockhash/RngBlockhash.sol";

import { DrawManager } from "pt-v5-draw-manager/DrawManager.sol";
import { FeeBurner } from "pt-v5-prize-pool-fee-burner/FeeBurner.sol";

import { TwabController } from "pt-v5-twab-controller/TwabController.sol";
import { PrizePool, ConstructorParams } from "pt-v5-prize-pool/PrizePool.sol";

import { Claimer } from "pt-v5-claimer/Claimer.sol";

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidationPairFactory } from "pt-v5-cgda-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter } from "pt-v5-cgda-liquidator/LiquidationRouter.sol";

import { YieldVaultMintRate } from "../YieldVaultMintRate.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";
import { Utils } from "../utils/Utils.sol";

contract SingleChainEnvironment is Config, Constant, Utils, StdCheats {
  ERC20PermitMock public prizeToken;
  ERC20PermitMock public poolToken;
  PrizePool public prizePool;
  RngBlockhash public rng;

  DrawManager public drawManager;
  
  TwabController public twab;

  ERC20PermitMock public underlyingToken;
  PrizeVaultFactory public vaultFactory;
  PrizeVault public vault;
  YieldVaultMintRate public yieldVault;
  ILiquidationPair public pair;
  Claimer public claimer;
  LiquidationRouter public router;

  FeeBurner public feeBurner;
  ILiquidationPair public feeBurnerPair;

  address[] public users;

  GasConfig internal _gasConfig;

  constructor(
    PrizePoolConfig memory _prizePoolConfig,
    ClaimerConfig memory _claimerConfig,
    RngAuctionConfig memory _rngAuctionConfig,
    GasConfig memory gasConfig_
  ) {
    _gasConfig = gasConfig_;

    twab = new TwabController(
      _prizePoolConfig.drawPeriodSeconds,
      _getTwabControllerOffset(_prizePoolConfig)
    );

    prizeToken = new ERC20PermitMock("WETH");
    poolToken = new ERC20PermitMock("POOL");

    prizePool = new PrizePool(
      ConstructorParams({
        prizeToken: prizeToken,
        twabController: twab,
        creator: address(this),
        tierLiquidityUtilizationRate: _prizePoolConfig.tierLiquidityUtilizationRate,
        drawPeriodSeconds: _prizePoolConfig.drawPeriodSeconds,
        firstDrawOpensAt: _prizePoolConfig.firstDrawOpensAt,
        grandPrizePeriodDraws: _prizePoolConfig.grandPrizePeriodDraws,
        numberOfTiers: _prizePoolConfig.numberOfTiers,
        tierShares: _prizePoolConfig.tierShares,
        canaryShares: _prizePoolConfig.canaryShares,
        reserveShares: _prizePoolConfig.reserveShares,
        drawTimeout: _prizePoolConfig.drawTimeout
      })
    );

    rng = new RngBlockhash();
    feeBurner = new FeeBurner(prizePool, address(poolToken), address(this));
    drawManager = new DrawManager(
      prizePool,
      rng,
      _rngAuctionConfig.auctionDuration,
      _rngAuctionConfig.auctionTargetTime,
      _rngAuctionConfig.firstAuctionTargetRewardFraction,
      _getFirstRngRelayAuctionTargetRewardFraction(),
      AUCTION_MAX_REWARD,
      address(feeBurner)
    );

    prizePool.setDrawManager(address(drawManager));

    underlyingToken = new ERC20PermitMock("USDC");
    yieldVault = new YieldVaultMintRate(underlyingToken, "Yearnish yUSDC", "yUSDC", address(this));

    vaultFactory = new PrizeVaultFactory();

    claimer = new Claimer(
      prizePool,
      _claimerConfig.minimumFee,
      _claimerConfig.maximumFee,
      _claimerConfig.timeToReachMaxFee,
      _claimerConfig.maxFeePortionOfPrize
    );

    vault = PrizeVault(
      vaultFactory.deployVault(
        "PoolTogether Prize USDC",
        "pzUSDC",
        yieldVault,
        prizePool,
        address(claimer),
        address(0), // yield fee recipient
        0, // yield fee
        1e5, // yield buffer
        address(this)
      )
    );
  }

  function gasConfig() public view returns(GasConfig memory) {
    return _gasConfig;
  }

  function initializeCgdaLiquidator(
    SD59x18 wethUsdValue, // usd / weth
    SD59x18 poolUsdValue, // usd / pool
    CgdaLiquidatorConfig memory _liquidatorConfig
  ) external virtual {
    LiquidationPairFactory pairFactory = new LiquidationPairFactory();
    vm.label(address(pairFactory), "LiquidationPairFactory");
    LiquidationRouter cgdaRouter = new LiquidationRouter(pairFactory);
    vm.label(address(cgdaRouter), "LiquidationRouter");
    // console2.log(
    //   "initializeCgdaLiquidator _liquidatorConfig.exchangeRatePrizeTokenToUnderlying",
    //   _liquidatorConfig.exchangeRatePrizeTokenToUnderlying.unwrap()
    // );

    // selling "pool" for weth.
    // so we want 

    uint104 poolAmount = 1e18; // 1 WETH
    // convert pool => weth
    // 1 pool = ? weth
    // 1 pool * usd/pool = usd
    // usd / usd/weth = weth
    uint104 wethAmount = uint104(uint(convert(poolUsdValue.mul(convert(int(uint(poolAmount)))).div(wethUsdValue))));
    
    pair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(vault)),
          address(prizeToken),
          address(vault),
          _liquidatorConfig.periodLength,
          _liquidatorConfig.periodOffset,
          _liquidatorConfig.targetFirstSaleTime,
          _getDecayConstant(_liquidatorConfig.periodLength),
          wethAmount, // weth is token in
          poolAmount, // pool is token out
          1e18 // min is 1 pool being sold
        )
      )
    );
    vm.label(address(pair), "VaultLiquidationPair");

    router = LiquidationRouter(address(cgdaRouter));
    vault.setLiquidationPair(address(pair));

    feeBurnerPair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(feeBurner)),
          address(poolToken),
          address(prizeToken),
          _liquidatorConfig.periodLength,
          _liquidatorConfig.periodOffset,
          _liquidatorConfig.targetFirstSaleTime,
          _getDecayConstant(_liquidatorConfig.periodLength),
          poolAmount, // pool is token in (burn)
          wethAmount, // weth is token out
          wethAmount // 1 pool worth of weth being sold
        )
      )
    );
    vm.label(address(feeBurnerPair), "FeeBurnerLiquidationPair");

    feeBurner.setLiquidationPair(address(feeBurnerPair));
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

  function removeUsers() external {
    for (uint256 i = 0; i < users.length; i++) {
      address user = users[i];
      vm.startPrank(user);
      vault.withdraw(vault.balanceOf(user), user, user);
      vm.stopPrank();
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
