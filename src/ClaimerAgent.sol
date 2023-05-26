// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { Environment } from "src/Environment.sol";
import { Claim } from "v5-claimer/Claimer.sol";

contract ClaimerAgent {

    struct Draw {
        Winner[] winners;
        uint256 currentClaimIndex;
    }

    mapping(uint256 => Draw) draws;
    uint256 currentDrawIndex;

    Environment public env;

    constructor (Environment _env) {
        env = _env;
    }

    function check() public {
        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        if (drawId > 0 && drawId > currentDrawIndex) {
            computePrizes();
        }

        uint claimCostInPrizeTokens = env.gasConfig().gasUsagePerClaim * env.gasConfig().gasPriceInPrizeTokens;

        uint profitableCount = 0;
        for (uint i = draws[drawId].currentClaimIndex; i < env.userCount()*env.prizePool().numberOfTiers(); i++) {
            // env.claimer().claimPrizes(
            //     drawId,

            // )
        }

    }

    function computePrizes() public {
        uint256 drawId = env.prizePool().getLastCompletedDrawId();
        require(drawId >= currentDrawIndex, "invalid draw");
        address vault = address(env.vault());
        for (uint i = 0; i < env.userCount(); i++) {
            address user = env.users(i);
            for (uint8 t = 0; t <= env.prizePool().numberOfTiers(); i++) {
                if (env.prizePool().isWinner(vault, user, t)) {
                    draws[drawId].winners.push(Claim(vault, user, t));
                }
            }
        }

        currentDrawIndex = drawId;
    }

}
