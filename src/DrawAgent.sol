pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment, GasConfig } from "src/Environment.sol";

contract DrawAgent {

    Environment public env;

    uint public drawCount;

    constructor (Environment _env) {
        env = _env;
    }

    function check() public {

        GasConfig memory gasConfig = env.gasConfig();
        uint cost = gasConfig.gasUsagePerCompleteDraw * gasConfig.gasPriceInPrizeTokens;
        uint minimum = cost + (cost / 10); // require 10% profit
        if (env.prizePool().hasNextDrawFinished()) {
            uint nextReserve = env.prizePool().reserve() + env.prizePool().reserveForNextDraw();
            if (nextReserve >= minimum) {
                console2.log("DrawAgent Draw ", env.prizePool().getNextDrawId(), "Block Timestamp - last draw start", block.timestamp - env.prizePool().lastCompletedDrawStartedAt());
                env.prizePool().completeAndStartNextDraw(uint256(keccak256(abi.encodePacked(block.timestamp))));
                env.prizePool().withdrawReserve(address(this), uint104(minimum));
                drawCount++;
            } else {
                console2.log("Insufficient reserve to draw", env.prizePool().getNextDrawId(), "Block Timestamp - last draw start", block.timestamp - env.prizePool().lastCompletedDrawStartedAt());
            }
        }
    }
}
