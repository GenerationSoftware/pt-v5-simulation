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

    uint256 public totalNormalPrizesComputed;
    uint256 public totalCanaryPrizesComputed;

    uint256 public totalNormalPrizesClaimed;
    uint256 public totalCanaryPrizesClaimed;

    uint256 public totalFees;

    mapping(uint256 => uint8) public drawNumberOfTiers;
    mapping(uint256 => mapping(uint8 => uint256)) public drawNormalTierComputedPrizeCounts;
    mapping(uint256 => mapping(uint8 => uint256)) public drawNormalTierClaimedPrizeCounts;

    Environment public env;

    uint constant INSPECT_DRAW_ID = 400;

    constructor (Environment _env) {
        env = _env;
    }

    function getPrize(uint drawId, uint prizeIndex) external view returns (Prize memory) {
        return drawPrizes[drawId][prizeIndex];
    }

    function getPrizeCount(uint drawId) external view returns (uint256) {
        return drawPrizes[drawId].length;
    }

    function logDraw(uint drawId) public view returns (bool) {
        return drawId == INSPECT_DRAW_ID;
    }

    function check() public returns (uint256) {
        // console2.log("ClaimerAgent checking", block.timestamp);
        uint drawId = env.prizePool().getLastCompletedDrawId();

        if (drawId != computedDrawId) {
            computePrizes();
        }

        uint totalFeesForBatch;

        uint claimCostInPrizeTokens = env.gasConfig().gasUsagePerClaim * env.gasConfig().gasPriceInPrizeTokens;

        uint8 numTiers = env.prizePool().numberOfTiers();

        if (logDraw(drawId)) {
            console2.log("\tClaim cost (cents): ", claimCostInPrizeTokens/1e16);
        }

        uint256 remainingPrizes = drawPrizes[computedDrawId].length - nextPrizeIndex;
        while (remainingPrizes > 0) {
            (uint8 tier, uint256 tierPrizes) = countContiguousTierPrizes(nextPrizeIndex, remainingPrizes);

            uint claimFees;
            uint targetClaimCount;
            // see if any are worth claiming
            for (uint i = 1; i < tierPrizes+1; i++) {
                uint nextClaimFees = env.claimer().computeTotalFees(tier, i);
                if (logDraw(drawId)) {
                    // console2.log("\tclaim count/fee", i, nextClaimFees, block.timestamp);
                }
                if (nextClaimFees - claimFees > claimCostInPrizeTokens) {
                    targetClaimCount = i;
                    claimFees = nextClaimFees;
                } else {
                    break;
                }
            }

            if (targetClaimCount > 0) {
                // count winners
                uint256 winnersLength = countWinners(nextPrizeIndex, targetClaimCount);

                // count prize indices per winner
                uint32[] memory prizeIndexLength = countPrizeIndicesPerWinner(nextPrizeIndex, targetClaimCount, winnersLength);

                // build result arrays
                (address[] memory winners, uint32[][] memory prizeIndices) = populateArrays(nextPrizeIndex, targetClaimCount, winnersLength, prizeIndexLength);

                if (logDraw(drawId)) {
                    console2.log("+++++++++++++++++++++ $$$$$$$$$$$$$$$$$$ Claiming prizes", tier, targetClaimCount);
                }

                if (tier == 0) {
                    console2.log("+++++++++++++++++++++ $ Claiming Grand prize of ", env.prizePool().getTierPrizeSize(0));
                }

                totalFeesForBatch += env.claimer().claimPrizes(env.vault(), tier, winners, prizeIndices, address(this));

                if (tier != numTiers - 1) {
                    totalNormalPrizesClaimed += targetClaimCount;
                    drawNormalTierClaimedPrizeCounts[computedDrawId][tier] += targetClaimCount;
                } else {
                    totalCanaryPrizesClaimed += targetClaimCount;
                }

                nextPrizeIndex += targetClaimCount;
                remainingPrizes = drawPrizes[computedDrawId].length - nextPrizeIndex;
            } else {
                break;
            }
        }

        totalFees += totalFeesForBatch;

        return totalFeesForBatch;
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

    function countTierPrizes(uint8 _tier) public view returns (uint256) {
        uint32 tierPrizes;
        for (uint p = 0; p < drawPrizes[computedDrawId].length; p++) {
            if (drawPrizes[computedDrawId][p].tier == _tier) {
                tierPrizes++;
            }
        }
        return tierPrizes;
    }

    function computePrizes() public {
        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        require(drawId >= computedDrawId, "invalid draw");
        Vault vault = env.vault();
        uint8 numTiers = env.prizePool().numberOfTiers();
        drawNumberOfTiers[drawId] = numTiers;
        for (uint8 t = 0; t < numTiers; t++) { // make sure canary tier is last
            for (uint i = 0; i < env.userCount(); i++) {
                address user = env.users(i);
                for (uint32 p = 0; p < env.prizePool().getTierPrizeCount(t); p++) {
                    if (env.prizePool().isWinner(address(vault), user, t, p)) {
                        drawPrizes[drawId].push(Prize(t, user, p));

                        if (t != numTiers - 1) {
                            totalNormalPrizesComputed++;
                            drawNormalTierComputedPrizeCounts[drawId][t]++;
                        } else {
                            totalCanaryPrizesComputed++;
                        }
                    }
                }
            }
        }
        computedDrawId = drawId;
        nextPrizeIndex = 0;

        // console2.log("+++++++++++++++++++++ Total Normal Prizes Computed", drawNormalTierComputedPrizeCounts[drawId][t]);

        if (logDraw(drawId)) {

            console2.log("+++++++++++++++++++++ Prize Claim Cost (cents):", (env.gasConfig().gasUsagePerClaim * env.gasConfig().gasPriceInPrizeTokens) / 1e16);
            console2.log("+++++++++++++++++++++ Draw", drawId, "has winners: ", drawPrizes[drawId].length);
            console2.log("+++++++++++++++++++++ Draw", drawId, "has tiers (inc. canary): ", env.prizePool().numberOfTiers());
            console2.log("+++++++++++++++++++++ Expected Prize Count", env.prizePool().estimatedPrizeCount());
            
            for (uint8 t = 0; t < env.prizePool().numberOfTiers(); t++) {
                uint prizeSize = env.prizePool().getTierPrizeSize(t) / 1e16;
                console2.log("\t\t\tTier", t);
                console2.log("\t\t\t\tprize size (cents): ", prizeSize, "prize count: ", countTierPrizes(t));
            }
            console2.log("\t\t\tReserve", env.prizePool().reserve() / 1e18);

        }
        

    }
}
