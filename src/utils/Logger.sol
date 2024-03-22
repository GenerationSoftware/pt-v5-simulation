// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { CommonBase } from "forge-std/Base.sol";

struct DrawLog {
    uint24 drawId;
    uint8 numberOfTiers;
    uint256 startDrawReward;
    uint256 finishDrawReward;
    string reserveLiquidationAmountOutUsd;
    string reserveLiquidationAmountInUsd;
    uint256 burnedPool;
    uint256 apr;
    string totalLiquidationAmountOutUsd;
    string totalLiquidationAmountInUsd;
    uint256[11] tierLiquidityRemaining;
    uint256[11] tierPrizeSizes;
    string[11] tierPrizeSizesUsd;
    uint256[11] claimedPrizes;
    uint256[11] computedPrizes;
}

contract Logger is CommonBase {

    string public outputFilepath;

    constructor(string memory _outputFilepath) {
        outputFilepath = _outputFilepath;
        vm.writeLine(outputFilepath, "Draw id, Number of Tiers, apr, Total Yield Amount Out (usd), Total Liquidation Amount In (usd), Total Reserve Out (usd), Total Pool Burned (usd), POOL Burned, Start Draw Reward, Finish Draw Reward, tier1LiquidityRemaining, tier2LiquidityRemaining, tier3LiquidityRemaining, tier4LiquidityRemaining, tier5LiquidityRemaining, tier6LiquidityRemaining, tier7LiquidityRemaining, tier8LiquidityRemaining, tier9LiquidityRemaining, tier10LiquidityRemaining, tier11LiquidityRemaining, tier1PrizeSizes, tier2PrizeSizes, tier3PrizeSizes, tier4PrizeSizes, tier5PrizeSizes, tier6PrizeSizes, tier7PrizeSizes, tier8PrizeSizes, tier9PrizeSizes, tier10PrizeSizes, tier11PrizeSizes, tier1PrizeSizesUsd, tier2PrizeSizesUsd, tier3PrizeSizesUsd, tier4PrizeSizesUsd, tier5PrizeSizesUsd, tier6PrizeSizesUsd, tier7PrizeSizesUsd, tier8PrizeSizesUsd, tier9PrizeSizesUsd, tier10PrizeSizesUsd, tier11PrizeSizesUsd, tier1ClaimedPrizes, tier2ClaimedPrizes, tier3ClaimedPrizes, tier4ClaimedPrizes, tier5ClaimedPrizes, tier6ClaimedPrizes, tier7ClaimedPrizes, tier8ClaimedPrizes, tier9ClaimedPrizes, tier10ClaimedPrizes, tier11ClaimedPrizes, tier1ComputedPrizes, tier2ComputedPrizes, tier3ComputedPrizes, tier4ComputedPrizes, tier5ComputedPrizes, tier6ComputedPrizes, tier7ComputedPrizes, tier8ComputedPrizes, tier9ComputedPrizes, tier10ComputedPrizes, tier11ComputedPrizes");
    }

    function log(DrawLog memory _log) public {
        uint8 size = 65;
        string[] memory data = new string[](size);
        data[0] = vm.toString(_log.drawId);
        data[1] = vm.toString(_log.numberOfTiers);
        data[2] = vm.toString(_log.apr);
        data[3] = _log.totalLiquidationAmountOutUsd;
        data[4] = _log.totalLiquidationAmountInUsd;
        data[5] = _log.reserveLiquidationAmountOutUsd;
        data[6] = _log.reserveLiquidationAmountInUsd;
        data[7] = vm.toString(_log.burnedPool);
        data[8] = vm.toString(_log.startDrawReward);
        data[9] = vm.toString(_log.finishDrawReward);
        for (uint8 i = 0; i < 11; i++) {
            data[i + 10] = vm.toString(_log.tierLiquidityRemaining[i]);
            data[i + 21] = vm.toString(_log.tierPrizeSizes[i]);
            data[i + 32] = _log.tierPrizeSizesUsd[i];
            data[i + 43] = vm.toString(_log.claimedPrizes[i]);
            data[i + 54] = vm.toString(_log.computedPrizes[i]);
        }

        string memory result = data[0];
        for (uint8 i = 1; i < size; i++) {
            result = string.concat(result, ",", data[i]);
        }

        vm.writeLine(outputFilepath, result);
    }

    function close() public {
        vm.closeFile(outputFilepath);
    }
}