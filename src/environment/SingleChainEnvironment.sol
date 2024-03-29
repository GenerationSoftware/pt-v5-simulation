// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

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

// import { LiquidationPairFactory } from "pt-v5-cgda-liquidator/LiquidationPairFactory.sol";
// import { LiquidationRouter } from "pt-v5-cgda-liquidator/LiquidationRouter.sol";
import { FixedLiquidationPairFactory } from "fixed-liquidator/FixedLiquidationPairFactory.sol";
import { FixedLiquidationRouter } from "fixed-liquidator/FixedLiquidationRouter.sol";

import { YieldVaultMintRate } from "../YieldVaultMintRate.sol";

import { Utils } from "../utils/Utils.sol";
import {
  Config,
  SimulationConfig,
  PrizePoolConfig,
  LiquidatorConfig,
  ClaimerConfig,
  DrawManagerConfig,
  GasConfig
} from "../utils/Config.sol";

contract SingleChainEnvironment is Utils, StdCheats {

  Config public config;

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
  FixedLiquidationRouter public router;
  FeeBurner public feeBurner;
  ILiquidationPair public feeBurnerPair;

  address[] public users;

  constructor(Config _config) {
    config = _config;

    SimulationConfig memory simulationConfig = config.simulation();
    PrizePoolConfig memory prizePoolConfig = config.prizePool();
    LiquidatorConfig memory liquidatorConfig = config.liquidator();
    ClaimerConfig memory claimerConfig = config.claimer();
    DrawManagerConfig memory drawManagerConfig = config.drawManager();
    GasConfig memory gasConfig = config.gas();

    // console2.log("SingleChainEnvironment constructor 1");

    twab = new TwabController(
      prizePoolConfig.drawPeriodSeconds,
      config.getTwabControllerOffset()
    );

    // console2.log("SingleChainEnvironment constructor 2");

    prizeToken = new ERC20PermitMock("WETH");
    poolToken = new ERC20PermitMock("POOL");

    prizePool = new PrizePool(
      ConstructorParams({
        prizeToken: prizeToken,
        twabController: twab,
        creator: address(this),
        tierLiquidityUtilizationRate: prizePoolConfig.tierLiquidityUtilizationRate,
        drawPeriodSeconds: prizePoolConfig.drawPeriodSeconds,
        firstDrawOpensAt: prizePoolConfig.firstDrawOpensAt,
        grandPrizePeriodDraws: prizePoolConfig.grandPrizePeriodDraws,
        numberOfTiers: prizePoolConfig.numberOfTiers,
        tierShares: prizePoolConfig.tierShares,
        canaryShares: prizePoolConfig.canaryShares,
        reserveShares: prizePoolConfig.reserveShares,
        drawTimeout: prizePoolConfig.drawTimeout
      })
    );

    // console2.log("SingleChainEnvironment constructor 3");

    rng = new RngBlockhash();
    feeBurner = new FeeBurner(prizePool, address(poolToken), address(this));
    drawManager = new DrawManager(
      prizePool,
      rng,
      drawManagerConfig.auctionDuration,
      drawManagerConfig.auctionTargetTime,
      drawManagerConfig.firstAuctionTargetRewardFraction,
      config.getFirstRngRelayAuctionTargetRewardFraction(),
      drawManagerConfig.auctionMaxReward,
      address(feeBurner)
    );

    prizePool.setDrawManager(address(drawManager));

    // console2.log("SingleChainEnvironment constructor 4");

    underlyingToken = new ERC20PermitMock("USDC");
    yieldVault = new YieldVaultMintRate(underlyingToken, "Yearnish yUSDC", "yUSDC", address(this));

    vaultFactory = new PrizeVaultFactory();

    // console2.log("SingleChainEnvironment constructor 5");


    claimer = new Claimer(
      prizePool,
      claimerConfig.minimumFee,
      claimerConfig.maximumFee,
      claimerConfig.timeToReachMaxFee,
      claimerConfig.maxFeePortionOfPrize
    );

    console2.log("Claimer DecayConstant ", claimer.decayConstant().unwrap());
    // console2.log("SingleChainEnvironment constructor 6");

    underlyingToken.mint(address(this), vaultFactory.YIELD_BUFFER());
    underlyingToken.approve(address(vaultFactory), vaultFactory.YIELD_BUFFER());
    vault = PrizeVault(
      vaultFactory.deployVault(
        "PoolTogether Prize USDC",
        "pzUSDC",
        yieldVault,
        prizePool,
        address(claimer),
        address(0), // yield fee recipient
        0, // yield fee
        address(this)
      )
    );


    initializeCgdaLiquidator(liquidatorConfig);
    // console2.log("config.simulation().totalValueLocked: ", config.simulation().totalValueLocked);
    addUsers(config.simulation().numUsers, config.simulation().totalValueLocked / config.simulation().numUsers);
  }

  function initializeCgdaLiquidator(LiquidatorConfig memory _liquidatorConfig) public virtual {
    SD59x18 wethUsdValue = config.wethUsdValueOverTime().get(block.timestamp);
    SD59x18 poolUsdValue = config.poolUsdValueOverTime().get(block.timestamp);

    FixedLiquidationPairFactory pairFactory = new FixedLiquidationPairFactory();
    vm.label(address(pairFactory), "FixedLiquidationPairFactory");
    FixedLiquidationRouter fixedRouter = new FixedLiquidationRouter(pairFactory);
    vm.label(address(fixedRouter), "FixedLiquidationRouter");
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
          config.prizePool().drawPeriodSeconds / 3,
          0.00001e18,
          0 // no smoothing
        )
      )
    );
    vm.label(address(pair), "VaultLiquidationPair");

    router = FixedLiquidationRouter(address(fixedRouter));
    vault.setLiquidationPair(address(pair));

    feeBurnerPair = ILiquidationPair(
      address(
        pairFactory.createPair(
          ILiquidationSource(address(feeBurner)),
          address(poolToken),
          address(prizeToken),
          config.prizePool().drawPeriodSeconds / 3,
          1e18, // 1 POOL,
          0.95e18 // very high smoothing
        )
      )
    );
    vm.label(address(feeBurnerPair), "FeeBurnerLiquidationPair");

    feeBurner.setLiquidationPair(address(feeBurnerPair));
  }

  function addUsers(uint256 count, uint256 depositSize) public {
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

  function removeUsers() public {
    for (uint256 i = 0; i < users.length; i++) {
      address user = users[i];
      vm.startPrank(user);
      vault.withdraw(vault.balanceOf(user), user, user);
      vm.stopPrank();
    }
  }

  function userCount() public view returns (uint256) {
    return users.length;
  }

  function mintYield() public returns (uint) {
    return yieldVault.mintRate();
  }

  function updateApr() public returns (uint256) {
    uint256 apr = config.aprOverTime().get(block.timestamp);
    yieldVault.setRatePerSecond(apr / 365 days);
    return apr;
  }
}
