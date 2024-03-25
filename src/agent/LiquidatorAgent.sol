// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { SD59x18, wrap, convert, uMAX_SD59x18 } from "prb-math/SD59x18.sol";

import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { FixedLiquidationPair } from "fixed-liquidator/FixedLiquidationPair.sol";
import { FixedLiquidationRouter } from "fixed-liquidator/FixedLiquidationRouter.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

import { SingleChainEnvironment } from "../environment/SingleChainEnvironment.sol";

import { Config } from "../utils/Config.sol";
import { Utils } from "../utils/Utils.sol";

contract LiquidatorAgent is Utils {
  string liquidatorCsvFile = string.concat(vm.projectRoot(), "/data/liquidatorOut.csv");
  string liquidatorCsvColumns =
    "Draw ID, Timestamp, Elapsed Time, Elapsed Percent, Availability, Amount In, Amount Out, Exchange Rate, Market Exchange Rate, Profit, Efficiency, Remaining Yield";

  SingleChainEnvironment public env;

  PrizePool public prizePool;
  ERC20PermitMock public prizeToken;
  FixedLiquidationRouter public router;

  string liquidatorCsv;

  uint public burnedPool;

  mapping(uint24 drawId => uint256 totalBurnedPool) public totalBurnedPoolPerDraw;
  mapping(uint24 drawId => uint256 amountIn) public totalAmountInPerDraw;
  mapping(uint24 drawId => uint256 amountOut) public totalAmountOutPerDraw;
  mapping(uint24 drawId => uint256 amountIn) public feeBurnerAmountInPerDraw;
  mapping(uint24 drawId => uint256 amountOut) public feeBurnerAmountOutPerDraw;

  constructor(SingleChainEnvironment _env) {
    env = _env;

    prizePool = env.prizePool();
    prizeToken = env.prizeToken();
    router = env.router();

    initOutputFileCsv(liquidatorCsvFile, liquidatorCsvColumns);
    prizeToken.approve(address(router), type(uint256).max);
  }

  function check(SD59x18 wethUsdValue, SD59x18 poolUsdValue) public {
    uint256 amountOut;
    uint256 amountIn;
    SD59x18 profit;
    uint24 openDrawId = prizePool.getOpenDrawId();
    (amountOut, amountIn, profit) = checkLiquidationPair(wethUsdValue, poolUsdValue, wethUsdValue, env.pair());
    if (profit.gt(wrap(0))) {
      totalAmountInPerDraw[openDrawId] += amountIn;
      totalAmountOutPerDraw[openDrawId] += amountOut;
    }
    (amountOut, amountIn, profit) = checkLiquidationPair(poolUsdValue, wethUsdValue, wethUsdValue, env.feeBurnerPair());
    if (profit.gt(wrap(0))) {
      feeBurnerAmountInPerDraw[openDrawId] += amountIn;
      feeBurnerAmountOutPerDraw[openDrawId] += amountOut;
    }
  }

  function checkLiquidationPair(SD59x18 tokenInValueUsd, SD59x18 tokenOutValueUsd, SD59x18 ethValueUsd, ILiquidationPair pair) public returns (uint256 amountOut, uint256 amountIn, SD59x18 profit) {
    uint256 maxAmountOut = pair.maxAmountOut();

    (amountOut, amountIn, profit) = _findBestProfit(tokenInValueUsd, tokenOutValueUsd, ethValueUsd, pair);

    // if (isFeeBurner(pair) && maxAmountOut > 0) {
    // }
    // console2.log("checkLiquidationPair amountOut %e", amountOut);
    // console2.log("checkLiquidationPair amountIn %e", amountIn);

    if (profit.gt(wrap(0))) {
      ERC20PermitMock tokenIn = ERC20PermitMock(pair.tokenIn());
      tokenIn.mint(address(this), amountIn);
      tokenIn.approve(address(router), amountIn);
      router.swapExactAmountOut(
        FixedLiquidationPair(address(pair)),
        address(this),
        amountOut,
        uint256(uMAX_SD59x18 / 1e18), // NOTE: uMAX_SD59x18/1e18 for DaLiquidator
        block.timestamp + 10
      );
      if (isFeeBurner(pair)) {
        burnedPool += amountIn;
      }


      uint256 elapsedSinceDrawEnded;
      // uint256 elapsedSinceDrawEnded = block.timestamp -
      //   prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());


      // SD59x18 efficiency = convert(int256(amountIn)).div(convert(int256(amountOutInPrizeTokens)));
      // uint256 efficiencyPercent = uint256(convert(efficiency.mul(convert(100))));

      uint256[] memory logs = new uint256[](12);
      logs[0] = prizePool.getLastAwardedDrawId();
      logs[1] = block.timestamp;
      logs[2] = elapsedSinceDrawEnded;
      logs[3] = (elapsedSinceDrawEnded * 100) / 1 days;
      logs[4] = maxAmountOut;
      logs[5] = amountIn;
      logs[6] = amountOut;
      logs[7] = amountIn / amountOut;
      logs[8] = 0;
      logs[9] = 0; //convert(profit);
      logs[10] = 0;
      logs[11] = pair.maxAmountOut();


      logUint256ToCsv(liquidatorCsvFile, logs);
    }    
  }

  function _findBestProfit(
    SD59x18 tokenInValueUsd,
    SD59x18 tokenOutValueUsd,
    SD59x18 ethValueUsd,
    ILiquidationPair pair
  ) internal returns (uint256 actualAmountOut, uint256 actualAmountIn, SD59x18 profit) {
    uint256 maxAmountOut = pair.maxAmountOut();

    uint256 liquidationSearchDensity = env.config().liquidator().liquidationPairSearchDensity;

    for (uint i = 1; i <= liquidationSearchDensity; i++) {
      uint256 amountOut = (maxAmountOut/liquidationSearchDensity) * i;
      if (amountOut == 0) {
        continue;
      }
      uint256 amountIn = pair.computeExactAmountIn(amountOut);
      SD59x18 swapProfit = computeProfit(tokenInValueUsd, tokenOutValueUsd, ethValueUsd, amountIn, amountOut);
      if (swapProfit.gt(profit)) {
        profit = swapProfit;
        actualAmountOut = amountOut;
        actualAmountIn = amountIn;
      }
    }
  }

  function computeProfit(
    SD59x18 tokenInValueUsd,
    SD59x18 tokenOutValueUsd,
    SD59x18 ethValueUsd,
    uint256 amountIn,
    uint256 amountOut
  ) public view returns (SD59x18) {
    SD59x18 amountOutInUsd = tokenOutValueUsd.mul(convert(int256(amountOut)));
    if (amountIn > 57896044618658097711785492504343953926634992332820282019728) {
      return wrap(0);
    }
    SD59x18 capitalCost = tokenInValueUsd.mul(convert(int256(amountIn)));//.add(convert(int256(env.config().gas().liquidationCostInUsd)));
    SD59x18 cost = capitalCost.add(convert(int256(env.config().gas().liquidationCostInUsd)));
    return cost.lt(amountOutInUsd) ? amountOutInUsd.sub(cost) : wrap(0);
  } 

  function isFeeBurner(ILiquidationPair pair) public view returns (bool) {
    return address(pair) == address(env.feeBurnerPair());
  }
}
