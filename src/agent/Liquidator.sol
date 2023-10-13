// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "forge-std/console2.sol";

import { SD59x18, wrap, convert, uMAX_SD59x18 } from "prb-math/SD59x18.sol";

import { ERC20PermitMock } from "pt-v5-vault-test/contracts/mock/ERC20PermitMock.sol";
import { ILiquidationPair } from "pt-v5-liquidator-interfaces/ILiquidationPair.sol";
import { LiquidationPair } from "pt-v5-cgda-liquidator/LiquidationPair.sol";
import { LiquidationRouter } from "pt-v5-cgda-liquidator/LiquidationRouter.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";

import { OptimismEnvironment } from "../environment/Optimism.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";
import { Utils } from "../utils/Utils.sol";

contract LiquidatorAgent is Config, Constant, Utils {
  string liquidatorCsvFile = string.concat(vm.projectRoot(), "/data/liquidatorOut.csv");
  string liquidatorCsvColumns =
    "Draw ID, Timestamp, Elapsed Time, Elapsed Percent, Availability, Amount In, Amount Out, Exchange Rate, Market Exchange Rate, Profit, Efficiency, Remaining Yield";

  OptimismGasConfig gasConfig = optimismGasConfig();
  OptimismEnvironment public env;

  PrizePool public prizePool;
  ERC20PermitMock public prizeToken;
  ILiquidationPair public pair;
  LiquidationRouter public router;

  uint256 totalApproxProfit;
  string liquidatorCsv;

  constructor(OptimismEnvironment _env) {
    env = _env;

    prizePool = env.prizePool();
    prizeToken = env.prizeToken();
    pair = env.pair();
    router = env.router();

    initOutputFileCsv(liquidatorCsvFile, liquidatorCsvColumns);
    prizeToken.approve(address(router), type(uint256).max);
  }

  function check(SD59x18 exchangeRatePrizeTokenToUnderlying) public {
    uint256 gasCostInPrizeTokens = gasConfig.gasPriceInPrizeTokens *
      gasConfig.gasUsagePerLiquidation;
    uint256 maxAmountOut = env.pair().maxAmountOut();

    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ checking maxAmountOut", maxAmountOut / 1e18);
    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ period", env.pair().getAuction().period);
    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ elapsed", env.pair().getElapsedTime());

    uint256 amountOut = maxAmountOut;
    uint256 amountIn = amountOut > 0 ? env.pair().computeExactAmountIn(amountOut) : 0;
    // console2.log("amountOut %s costs %s", amountOut, amountIn);
    uint256 profit;

    uint256 amountOutInPrizeTokens = uint256(
      convert(convert(int256(amountOut)).mul(exchangeRatePrizeTokenToUnderlying))
    );

    if (amountOutInPrizeTokens > amountIn) {
      profit = amountOutInPrizeTokens - amountIn;
    }

    if (profit > gasCostInPrizeTokens) {
      prizeToken.mint(address(this), amountIn);

      // console2.log("Swapping for amountOut: %s", amountOut);

      router.swapExactAmountOut(
        LiquidationPair(address(pair)),
        address(this),
        amountOut,
        uint256(uMAX_SD59x18 / 1e18), // NOTE: uMAX_SD59x18/1e18 for DaLiquidator
        block.timestamp + 10
      );

      totalApproxProfit += profit;

      uint256 elapsedSinceDrawEnded = block.timestamp -
        prizePool.drawClosesAt(prizePool.getLastAwardedDrawId());

      SD59x18 efficiency = convert(int256(amountIn)).div(convert(int256(amountOutInPrizeTokens)));
      uint256 efficiencyPercent = uint256(convert(efficiency.mul(convert(100))));

      uint256[] memory logs = new uint256[](12);
      logs[0] = prizePool.getLastAwardedDrawId();
      logs[1] = block.timestamp;
      logs[2] = elapsedSinceDrawEnded;
      logs[3] = (elapsedSinceDrawEnded * 100) / 1 days;
      logs[4] = maxAmountOut;
      logs[5] = amountIn;
      logs[6] = amountOut;
      logs[7] = amountIn / amountOut;
      logs[8] = uint256(SD59x18.unwrap(exchangeRatePrizeTokenToUnderlying));
      logs[9] = profit;
      logs[10] = efficiencyPercent;
      logs[11] = pair.maxAmountOut();

      logUint256ToCsv(liquidatorCsvFile, logs);

      // // NOTE: Percentage calc is hardcoded to 1 day.
      // console2.log(
      //   "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ @ %s (%s%)",
      //   elapsedSinceDrawEnded,
      //   (elapsedSinceDrawEnded * 100) / 1 days
      // );
      // console2.log(
      //   "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ LiquidatorAgent swapped POOL for Yield"
      // );
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tEfficiency\t", efficiencyPercent);
      // console2.log(
      //   "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tTarget ER\t",
      //   SD59x18.unwrap(LiquidationPair(address(env.pair())).targetExchangeRate())
      // );
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tAvailability\t", maxAmountOut);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tIn\t\t", amountIn);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tOut\t\t", amountOut);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tProfit\t\t", profit);
      // console2.log(
      //   "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tRemaining yield\t",
      //   env.pair().maxAmountOut()
      // );
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tGas cost", gasCostInPrizeTokens / 1e18);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Period, time", auction.period, block.timestamp);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ exchangeRatePrizeTokenToUnderlying", exchangeRatePrizeTokenToUnderlying);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ price average", env.pair().priceAverage().unwrap() / 1e18);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Accrued / claimed", uint(auction.amountAccrued) / 1e18, uint(auction.amountClaimed) / 1e18);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tcurrent time", block.timestamp);
      // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ \tauction time", env.pair().getPeriodStart());
      // console2.log("New reserve: ", env.pair().virtualReserveIn()/1e18, env.pair().virtualReserveOut()/1e18);
      // uint availableYield = env.vault().liquidatableBalanceOf(address(env.vault()));
      // console2.log("Available yield", availableYield, "/1e18:", availableYield / 1e18);
    }
  }
}
