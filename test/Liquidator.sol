// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import { LiquidatorLib } from "v5-liquidator-libraries/LiquidatorLib.sol";

contract LiquidatorTest is Test {

    function testLiquidatorLib_FavourableTradeCase() public {
        uint256 want0 = 372832611429953471237;
        uint128 reserve1 = 40417540831708944908300; // there is more of token 1 than token 2, so the trade rate should reflect that
        uint128 reserve0 = 23266309913322045335640;
        uint256 provide1 = LiquidatorLib.getAmountIn(want0, reserve1, reserve0);
        console2.log("Want",want0,"/1e18",want0/1e18);
        console2.log("Provide",provide1,"/1e18",provide1/1e18);
        assertGt(provide1, want0);
    }

}