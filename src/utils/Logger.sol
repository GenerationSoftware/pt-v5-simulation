// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import { CommonBase } from "forge-std/Base.sol";

struct DrawLog {
    uint24 drawId;
    uint8 numberOfTiers;
    uint256 startDrawReward;
    uint256 finishDrawReward;
    string reserveAmountContributedUsd;
    uint256 apr;
    string totalLiquidationAmountOutUsd;
    string totalLiquidationAmountInUsd;
    string totalContributed;
    string hookContributed;
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
        vm.writeLine(outputFilepath, "Draw id, Number of Tiers, apr, Total Yield Amount Out (usd), Total Liquidation Amount In (usd), Total Contrib (usd), Hook contrib (usd), POOL Vault Contrib. (usd), Start Draw Reward, Finish Draw Reward, tier0LiquidityRemaining, tier1LiquidityRemaining, tier2LiquidityRemaining, tier3LiquidityRemaining, tier4LiquidityRemaining, tier5LiquidityRemaining, tier6LiquidityRemaining, tier7LiquidityRemaining, tier8LiquidityRemaining, tier9LiquidityRemaining, tier10LiquidityRemaining, tier0PrizeSizes, tier1PrizeSizes, tier2PrizeSizes, tier3PrizeSizes, tier4PrizeSizes, tier5PrizeSizes, tier6PrizeSizes, tier7PrizeSizes, tier8PrizeSizes, tier9PrizeSizes, tier10PrizeSizes, tier0PrizeSizesUsd, tier1PrizeSizesUsd, tier2PrizeSizesUsd, tier3PrizeSizesUsd, tier4PrizeSizesUsd, tier5PrizeSizesUsd, tier6PrizeSizesUsd, tier7PrizeSizesUsd, tier8PrizeSizesUsd, tier9PrizeSizesUsd, tier10PrizeSizesUsd, tier0ClaimedPrizes, tier1ClaimedPrizes, tier2ClaimedPrizes, tier3ClaimedPrizes, tier4ClaimedPrizes, tier5ClaimedPrizes, tier6ClaimedPrizes, tier7ClaimedPrizes, tier8ClaimedPrizes, tier9ClaimedPrizes, tier10ClaimedPrizes, tier0ComputedPrizes, tier1ComputedPrizes, tier2ComputedPrizes, tier3ComputedPrizes, tier4ComputedPrizes, tier5ComputedPrizes, tier6ComputedPrizes, tier7ComputedPrizes, tier8ComputedPrizes, tier9ComputedPrizes, tier10ComputedPrizes");
    }

    function log(DrawLog memory _log) public {
        string memory result = logHeader(_log);
        for (uint8 i = 0; i < 11; i++) {
            result = string.concat(result, ",", vm.toString(_log.tierLiquidityRemaining[i]));
        }
        for (uint8 i = 0; i < 11; i++) {
            result = string.concat(result, ",", vm.toString(_log.tierPrizeSizes[i]));
        }
        for (uint8 i = 0; i < 11; i++) {
            result = string.concat(result, ",", _log.tierPrizeSizesUsd[i]);
        }
        for (uint8 i = 0; i < 11; i++) {
            result = string.concat(result, ",", vm.toString(_log.claimedPrizes[i]));
        }
        for (uint8 i = 0; i < 11; i++) {
            result = string.concat(result, ",", vm.toString(_log.computedPrizes[i]));
        }

        vm.writeLine(outputFilepath, result);
    }

    function logHeader(DrawLog memory _log) public returns (string memory) {
        return string.concat(
            vm.toString(_log.drawId), ",",
            vm.toString(_log.numberOfTiers), ",",
            vm.toString(_log.apr), ",",
            _log.totalLiquidationAmountOutUsd, ",",
            _log.totalLiquidationAmountInUsd, ",",
            logContributed(_log),
            vm.toString(_log.startDrawReward), ",",
            vm.toString(_log.finishDrawReward)
        );
    }

    function logContributed(DrawLog memory _log) public returns (string memory) {
        return string.concat(
            _log.totalContributed, ", ",
            _log.hookContributed, ", ",
            _log.reserveAmountContributedUsd, ","
        );
    }

    function close() public {
        vm.closeFile(outputFilepath);
    }
}