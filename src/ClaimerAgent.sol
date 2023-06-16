// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment } from "src/Environment.sol";
import { Vault } from "v5-vault/Vault.sol";

contract ClaimerAgent {

    struct Prize {
        uint8 tier;
        address winner;
        uint32 prizeIndex;
    }

    // draw => tier => Tier
    mapping(uint256 => Prize[]) internal drawPrizes;
    uint256 public nextPrizeIndex;
    uint256 public computedDrawId;

    Environment public env;

    constructor (Environment _env) {
        env = _env;
    }

    function getPrize(uint drawId, uint prizeIndex) external view returns (Prize memory) {
        return drawPrizes[drawId][prizeIndex];
    }

    function getPrizeCount(uint drawId) external view returns (uint256) {
        return drawPrizes[drawId].length;
    }

    function check() public {
        // console2.log("ClaimerAgent checking", block.timestamp);

        if (env.prizePool().getLastCompletedDrawId() != computedDrawId) {
            computePrizes();
        }

        // console2.log("check() 1");

        uint claimCostInPrizeTokens = env.gasConfig().gasUsagePerClaim * env.gasConfig().gasPriceInPrizeTokens;
        uint targetClaimCount = 0;
        uint claimFees = 0;
        uint256 remainingPrizes = drawPrizes[computedDrawId].length - nextPrizeIndex;
        for (uint i = 1; i < remainingPrizes; i++) {
            uint nextClaimFees = env.claimer().computeTotalFees(i);
            if (nextClaimFees - claimFees > claimCostInPrizeTokens) {
                targetClaimCount = i;
                claimFees = nextClaimFees;
            } else {
                break;
            }
        }

        if (targetClaimCount > 0) {
            console2.log("GO FOR CLAIMS", targetClaimCount);
            // console2.log("claimPrizes(computedDrawId, targetClaimCount)", computedDrawId, targetClaimCount);
            uint earned = claimPrizes(targetClaimCount);
            console2.log("CLAIMED ", targetClaimCount, " PRIZES. EARNED ", earned / 1e18);
            console2.log("\tmin claim fee: ", claimCostInPrizeTokens/1e18);
        }

    }

    function countContiguousTierPrizes(uint _nextPrizeIndex, uint _claimCount) public view returns (uint8 tier, uint256 count) {
        uint256 prizeCount;
        bool init = false;
        uint8 tier;
        for (uint p = _nextPrizeIndex; p < _nextPrizeIndex + _claimCount; p++) {
            if (!init) {
                tier = drawPrizes[computedDrawId][p].tier;
                init = true;
            }
            if (tier != drawPrizes[computedDrawId][p].tier) {
                break;
            }
            prizeCount++;
        }
        return (tier, prizeCount);
    }

    function countWinners(uint _nextPrizeIndex, uint _claimCount) public view returns (uint256 count) {
        uint256 winnersLength;
        address lastWinner;
        for (uint p = _nextPrizeIndex; p < _nextPrizeIndex + _claimCount; p++) {
            if (drawPrizes[computedDrawId][p].winner != lastWinner) {
                winnersLength++;
                lastWinner = drawPrizes[computedDrawId][p].winner;
            }
        }
        return winnersLength;
    }

    function countPrizeIndicesPerWinner(
        uint _nextPrizeIndex,
        uint _claimCount,
        uint _winnersLength
    ) public view returns (uint32[] memory prizeIndexLength) {
        uint256 winnersLength = countWinners(_nextPrizeIndex, _claimCount);
        prizeIndexLength = new uint32[](_winnersLength);
        uint256 winnerIndex;
        address currentWinner;
        for (uint p = _nextPrizeIndex; p < _nextPrizeIndex + _claimCount; p++) {
            if (currentWinner == address(0)) {
                currentWinner = drawPrizes[computedDrawId][p].winner;
            }
            if (currentWinner != drawPrizes[computedDrawId][p].winner) {
                winnerIndex++;
                currentWinner = drawPrizes[computedDrawId][p].winner;
            }
            prizeIndexLength[winnerIndex]++;
        }
    }

    function populateArrays(
        uint _nextPrizeIndex,
        uint _claimCount,
        uint _winnersLength,
        uint32[] memory _prizeIndexLength
    ) public view returns (address[] memory winners, uint32[][] memory prizeIndices) {
        winners = new address[](_winnersLength);
        prizeIndices = new uint32[][](_winnersLength);
        for (uint i = 0; i < _winnersLength; i++) {
            prizeIndices[i] = new uint32[](_prizeIndexLength[i]);
        }

        // populate result arrays
        uint winnerIndex = 0;
        address currentWinner;
        uint256 prizeIndex;
        for (uint pi = _nextPrizeIndex; pi < _nextPrizeIndex + _claimCount; pi++) {
            if (currentWinner == address(0)) {
                currentWinner = drawPrizes[computedDrawId][pi].winner;
                winners[winnerIndex] = currentWinner;
            }

            // if the current prize is for a different winner, then skip to next winner
            if (currentWinner != drawPrizes[computedDrawId][pi].winner) {
                winnerIndex++;
                prizeIndex = 0;
                currentWinner = drawPrizes[computedDrawId][pi].winner;
                winners[winnerIndex] = currentWinner;
            }

            prizeIndices[winnerIndex][prizeIndex] = drawPrizes[computedDrawId][pi].prizeIndex;

            prizeIndex++;
        }
    }

    function claimPrizes(uint targetClaimCount) public returns (uint) {
        uint256 remainingPrizes = drawPrizes[computedDrawId].length - nextPrizeIndex;
        uint256 claimCount = targetClaimCount > remainingPrizes ? remainingPrizes : targetClaimCount;

        uint totalFees;

        if (claimCount == 0) {
            return 0;
        }

        while (claimCount > 0) {
            (uint8 tier, uint256 tierPrizes) = countContiguousTierPrizes(nextPrizeIndex, claimCount);

            // console2.log("claimPrizes tier, tierPrizes", tier, tierPrizes);

            // count winners
            uint256 winnersLength = countWinners(nextPrizeIndex, tierPrizes);

            // console2.log("claimPrizes winnersLength", winnersLength);

            // count prize indices per winner
            uint32[] memory prizeIndexLength = countPrizeIndicesPerWinner(nextPrizeIndex, tierPrizes, winnersLength);

            // console2.log("claimPrizes prizeIndexLength", prizeIndexLength.length);

            // build result arrays
            (address[] memory winners, uint32[][] memory prizeIndices) = populateArrays(nextPrizeIndex, tierPrizes, winnersLength, prizeIndexLength);

            // console2.log("claimPrizes winnersLength", winners.length);

            totalFees += env.claimer().claimPrizes(env.vault(), tier, winners, prizeIndices, address(this));

            // console2.log("claimPrizes totalFees", totalFees);

            claimCount -= tierPrizes;
            nextPrizeIndex += tierPrizes;
        }

        return totalFees;
    }

    function computePrizes() public {
        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        require(drawId >= computedDrawId, "invalid draw");
        Vault vault = env.vault();
        for (uint i = 0; i < env.userCount(); i++) {
            address user = env.users(i);
            for (uint8 t = 0; t < env.prizePool().numberOfTiers(); t++) {
                for (uint32 p = 0; p < env.prizePool().getTierPrizeCount(t); p++) {
                    if (env.prizePool().isWinner(address(vault), user, t, p)) {
                        drawPrizes[drawId].push(Prize(t, user, p));
                    }
                }
            }
        }
        // console2.log("+++++++++++++++++++++++ Draw", drawId, "has winners: ", drawPrizes[drawId].length);
        // console2.log("canary prize size: ", env.prizePool().calculatePrizeSize(env.prizePool().numberOfTiers()) / 1e18);
        // console2.log("Tier 0 liquidity", env.prizePool().getRemainingTierLiquidity(0) / 1e18);
        // console2.log("Tier 1 liquidity", env.prizePool().getRemainingTierLiquidity(1) / 1e18);
        // console2.log("Tier 2 liquidity", env.prizePool().getRemainingTierLiquidity(2) / 1e18);
        // console2.log("Reserve", env.prizePool().reserve() / 1e18);
        computedDrawId = drawId;
        nextPrizeIndex = 0;
    }
}
