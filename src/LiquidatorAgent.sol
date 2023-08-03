pragma solidity 0.8.19;

import "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";

import { Environment } from "./Environment.sol";
import { SD59x18, wrap, convert, uMAX_SD59x18 } from "prb-math/SD59x18.sol";
import { LiquidationPair } from "pt-v5-cgda-liquidator/LiquidationPair.sol";

contract LiquidatorAgent {
  Environment public env;
  uint totalApproxProfit;
  string liquidatorCsv;
  Vm vm;

  constructor(Environment _env, Vm _vm) {
    env = _env;
    vm = _vm;
    initOutputFileCsv();
    env.prizeToken().approve(address(env.router()), type(uint).max);
  }

  function check(SD59x18 exchangeRatePrizeTokenToUnderlying) public {
    uint gasCostInPrizeTokens = env.gasConfig().gasPriceInPrizeTokens *
      env.gasConfig().gasUsagePerLiquidation;
    uint maxAmountOut = env.pair().maxAmountOut();

    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ checking maxAmountOut", maxAmountOut / 1e18);
    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ period", env.pair().getAuction().period);
    // console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ elapsed", env.pair().getElapsedTime());

    uint amountOut = maxAmountOut;
    uint amountIn = env.pair().computeExactAmountIn(amountOut);
    // console2.log("amountOut %s costs %s", amountOut, amountIn);
    uint profit;

    uint amountOutInPrizeTokens = uint(
      convert(convert(int(amountOut)).mul(exchangeRatePrizeTokenToUnderlying))
    );

    if (amountOutInPrizeTokens > amountIn) {
      profit = amountOutInPrizeTokens - amountIn;
    }

    if (profit > gasCostInPrizeTokens) {
      env.prizeToken().mint(address(this), amountIn);

      // console2.log("Swapping for amountOut: %s", amountOut);

      env.router().swapExactAmountOut(
        LiquidationPair(address(env.pair())),
        address(this),
        amountOut,
        uint(uMAX_SD59x18 / 1e18) // NOTE: uMAX_SD59x18/1e18 for DaLiquidator
        // type(uint).max // NOTE: type(uint).max for CgdaLiquidator
      );

      totalApproxProfit += profit;

      SD59x18 efficiency = convert(int(amountIn)).div(convert(int(amountOutInPrizeTokens)));
      uint efficiencyPercent = uint(convert(efficiency.mul(convert(100))));

      uint elapsedSinceDrawEnded = block.timestamp - env.prizePool().lastClosedDrawEndedAt();

      logToCsv(
        LiquidatorLog({
          drawId: env.prizePool().getLastClosedDrawId(),
          timestamp: block.timestamp,
          elapsedTime: elapsedSinceDrawEnded,
          elapsedPercent: (elapsedSinceDrawEnded * 100) / 1 days,
          availability: maxAmountOut,
          amountIn: amountIn,
          amountOut: amountOut,
          exchangeRate: amountIn / amountOut,
          marketExchangeRate: uint(SD59x18.unwrap(exchangeRatePrizeTokenToUnderlying)),
          profit: profit,
          efficiency: efficiencyPercent,
          remainingYield: env.pair().maxAmountOut()
        })
      );

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

  ////////////////////////// CSV LOGGING //////////////////////////

  struct LiquidatorLog {
    uint drawId;
    uint timestamp;
    uint elapsedTime;
    uint elapsedPercent;
    uint availability;
    uint amountIn;
    uint amountOut;
    uint exchangeRate;
    uint marketExchangeRate;
    uint profit;
    uint efficiency;
    uint remainingYield;
  }

  // Clears and logs the CSV headers to the file
  function initOutputFileCsv() public {
    liquidatorCsv = string.concat(vm.projectRoot(), "/data/liquidatorOut.csv");
    vm.writeFile(liquidatorCsv, "");
    vm.writeLine(
      liquidatorCsv,
      "Draw ID,Timestamp,Elapsed Time,Elapsed Percent,Availability,Amount In,Amount Out,Profit,Efficiency, Remaining Yield"
    );
  }

  function logToCsv(LiquidatorLog memory log) public {
    vm.writeLine(
      liquidatorCsv,
      string.concat(
        vm.toString(log.drawId),
        ",",
        vm.toString(log.timestamp),
        ",",
        vm.toString(log.elapsedTime),
        ",",
        vm.toString(log.elapsedPercent),
        ",",
        vm.toString(log.availability),
        ",",
        vm.toString(log.amountIn),
        ",",
        vm.toString(log.amountOut),
        ",",
        vm.toString(log.exchangeRate),
        ",",
        vm.toString(log.marketExchangeRate),
        ",",
        vm.toString(log.profit),
        ",",
        vm.toString(log.efficiency),
        ",",
        vm.toString(log.remainingYield)
      )
    );
  }

  /////////////////////////////////////////////////////////////////
}
