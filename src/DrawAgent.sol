pragma solidity 0.8.17;

import { Environment, GasConfig } from "src/Environment.sol";

contract DrawAgent {

    Environment public env;

    constructor (Environment _env) {
        env = _env;
    }

    function check() public {
        GasConfig memory gasConfig = env.gasConfig();
        uint cost = gasConfig.gasUsagePerCompleteDraw * gasConfig.gasPriceInPrizeTokens;
        uint minimum = cost + (cost / 10); // require 10% profit
        if (env.prizePool().hasNextDrawFinished()) {
            if (env.prizePool().reserve() >= minimum) {
                env.prizePool().completeAndStartNextDraw(uint256(keccak256(abi.encodePacked(block.timestamp))));
                env.prizePool().withdrawReserve(address(this), uint104(minimum));
            }
        }
    }
}
