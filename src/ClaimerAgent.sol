// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { Environment } from "src/Environment.sol";
import { Claim } from "v5-vrgda-claimer/Claimer.sol";
import { Vault } from "v5-vault/Vault.sol";
import { IVault } from "v5-vrgda-claimer/interfaces/IVault.sol";

contract ClaimerAgent {

    struct Draw {
        Claim[] winners;
        uint256 currentClaimIndex;
    }

    mapping(uint256 => Draw) draws;
    uint256 currentDrawIndex;

    Environment public env;

    constructor (Environment _env) {
        env = _env;
    }

    function check() public {
        // console2.log("ClaimerAgent checking", block.timestamp);

        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        if (drawId > 0 && drawId > currentDrawIndex) {
            computePrizes();
        }

        uint claimCostInPrizeTokens = env.gasConfig().gasUsagePerClaim * env.gasConfig().gasPriceInPrizeTokens;
        uint remainingClaims = draws[drawId].winners.length - draws[drawId].currentClaimIndex;
        uint claimCount = 0;
        uint claimFees = 0;
        for (uint i = 1; i < remainingClaims; i++) {
            uint nextClaimFees = env.claimer().computeTotalFees(i);
            console2.log("nextClaimFees", nextClaimFees);
            if (nextClaimFees - claimFees > claimCostInPrizeTokens) {
                claimCount = i;
                claimFees = nextClaimFees;
            } else {
                break;
            }
        }

        if (claimCount > 0) {
            Claim[] memory claims = new Claim[](claimCount);
            for (uint i = 0; i < claimCount; i++) {
                claims[i] = draws[drawId].winners[i + draws[drawId].currentClaimIndex];
            }
            env.claimer().claimPrizes(drawId, claims, address(this));
            console2.log("CLAIMING ", claimCount, " PRIZES");
            draws[drawId].currentClaimIndex += claimCount;
        }

    }

    function computePrizes() public {
        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        require(drawId >= currentDrawIndex, "invalid draw");
        Vault vault = env.vault();
        for (uint i = 0; i < env.userCount(); i++) {
            address user = env.users(i);
            for (uint8 t = 0; t <= env.prizePool().numberOfTiers(); t++) {
                if (env.prizePool().isWinner(address(vault), user, t)) {
                    console2.log("FOUND WINNER");
                    draws[drawId].winners.push(Claim(IVault(address(vault)), user, t));
                }
            }
        }

        currentDrawIndex = drawId;
    }

}
