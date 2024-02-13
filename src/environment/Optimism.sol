// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";
import { SD59x18, convert } from "prb-math/SD59x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";

import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";
import { PrizeVaultFactory } from "pt-v5-vault/PrizeVaultFactory.sol";
import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";

import { Claimer } from "pt-v5-claimer/Claimer.sol";

import { ILiquidationSource } from "pt-v5-liquidator-interfaces/ILiquidationSource.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";

import { LiquidationPairFactory } from "pt-v5-cgda-liquidator/LiquidationPairFactory.sol";
import { LiquidationRouter } from "pt-v5-cgda-liquidator/LiquidationRouter.sol";

import { YieldVaultMintRate } from "../YieldVaultMintRate.sol";

import { BaseEnvironment } from "./Base.sol";

contract OptimismEnvironment is BaseEnvironment {
  ERC20PermitMock public underlyingToken;
  PrizeVaultFactory public vaultFactory;
  PrizeVault public vault;
  YieldVaultMintRate public yieldVault;
  ILiquidationPair public pair;
  Claimer public claimer;
  LiquidationRouter public router;

  address[] public users;

  constructor(
    PrizePoolConfig memory _prizePoolConfig,
    ClaimerConfig memory _claimerConfig,
    RngAuctionConfig memory _rngAuctionConfig
  ) BaseEnvironment(_prizePoolConfig, _rngAuctionConfig) {
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

  function initializeCgdaLiquidator(
    CgdaLiquidatorConfig memory _liquidatorConfig
  ) external virtual {
    LiquidationPairFactory pairFactory = new LiquidationPairFactory();
    LiquidationRouter cgdaRouter = new LiquidationRouter(pairFactory);

    // console2.log(
    //   "initializeCgdaLiquidator _liquidatorConfig.exchangeRatePrizeTokenToUnderlying",
    //   _liquidatorConfig.exchangeRatePrizeTokenToUnderlying.unwrap()
    // );

    uint104 _initialAmountIn = 1e18; // 1 WETH
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
