// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { console2 } from "forge-std/console2.sol";
import { Vm } from "forge-std/Vm.sol";

import { Claimer } from "pt-v5-claimer/Claimer.sol";
import { PrizePool } from "pt-v5-prize-pool/PrizePool.sol";
import { PrizeVault } from "pt-v5-vault/PrizeVault.sol";

import { OptimismEnvironment } from "../environment/Optimism.sol";
import { Config } from "../utils/Config.sol";
import { Utils } from "../utils/Utils.sol";

contract ClaimerAgent is Config, Utils {
  string claimerCsvFile = string.concat(vm.projectRoot(), "/data/claimerOut.csv");
  string claimerCsvColumns = "Draw ID, Tier, Winner, Prize Index, Fees For Batch";

  OptimismGasConfig gasConfig = optimismGasConfig();
  OptimismEnvironment public env;

  Claimer public claimer;
  PrizePool public prizePool;
  PrizeVault public vault;

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
  mapping(uint256 => mapping(uint8 => uint256))
    public drawNormalTierInsufficientLiquidityPrizeCounts;
  mapping(uint256 => mapping(uint8 => uint256)) public drawNormalTierClaimedPrizeCounts;

  uint constant INSPECT_DRAW_ID = 400;

  uint logVerbosity;

  constructor(OptimismEnvironment _env, uint _logVerbosity) {
    env = _env;
    logVerbosity = _logVerbosity;

    claimer = env.claimer();
    prizePool = env.prizePool();
    vault = env.vault();

    initOutputFileCsv(claimerCsvFile, claimerCsvColumns);
  }

  function getPrize(uint drawId, uint prizeIndex) external view returns (Prize memory) {
    return drawPrizes[drawId][prizeIndex];
  }

  function getPrizeCount(uint drawId) external view returns (uint256) {
    return drawPrizes[drawId].length;
  }

  function isLogging(uint level) public view returns (bool) {
    return logVerbosity >= level;
  }

  function check() public returns (uint256) {
    uint drawId = prizePool.getLastAwardedDrawId();

    if (drawId != computedDrawId) {
      computePrizes();
    }

    uint totalFeesForBatch;
    uint256 remainingPrizes = drawPrizes[computedDrawId].length - nextPrizeIndex;

    while (remainingPrizes > 0) {
      (uint8 tier, uint256 tierPrizes) = countContiguousTierPrizes(nextPrizeIndex, remainingPrizes);

      uint targetClaimCount;
      uint prizeSize = prizePool.getTierPrizeSize(tier);

      for (uint currCount = tierPrizes; currCount > 0; currCount = currCount / 2) {
        // see if any are worth claiming
        {
          uint claimFees = claimer.computeTotalFees(tier, tierPrizes);
          uint cost = tierPrizes * gasConfig.gasUsagePerClaim * gasConfig.gasPriceInPrizeTokens;
          if (isLogging(3)) {
            console2.log(
              "\tclaimFees for drawId %s tier %s with prize size %e:",
              drawId,
              tier,
              prizeSize
            );
            console2.log(
              "\t\tfor %s prizes the fees are %e with cost %e",
              tierPrizes,
              claimFees,
              cost
            );
            console2.log("\tclaim (fees, count, cost)", claimFees, tierPrizes, cost);
          }
          if (claimFees > cost) {
            if (isLogging(3)) {
              console2.log("\t$ claiming (fees, count)", claimFees, tierPrizes);
            }
            targetClaimCount = tierPrizes;
            if (isLogging(3)) {
              console2.log("CLAIMING %s FOR TIER %s", tierPrizes, tier);
            }
          }
        }
      }

      uint32 maxPrizesPerLiquidity = uint32(prizePool.getTierRemainingLiquidity(tier) / prizeSize);

      if (targetClaimCount > maxPrizesPerLiquidity) {
        drawNormalTierInsufficientLiquidityPrizeCounts[drawId][tier] +=
          targetClaimCount -
          maxPrizesPerLiquidity;
        targetClaimCount = maxPrizesPerLiquidity;
        console2.log("INSUFFICIENT LIQUIDITY");
      }

      if (targetClaimCount > 0) {
        // count winners
        uint256 winnersLength = countWinners(nextPrizeIndex, targetClaimCount);

        // build result arrays
        (address[] memory winners, uint32[][] memory prizeIndices) = populateArrays(
          nextPrizeIndex,
          targetClaimCount,
          winnersLength,
          countPrizeIndicesPerWinner(nextPrizeIndex, targetClaimCount, winnersLength)
        );

        // if (isLogging(2)) {
        //   console2.log(
        //     "+++++++++++++++++++++ $$$$$$$$$$$$$$$$$$ Claiming prizes",
        //     tier,
        //     targetClaimCount
        //   );
        // }
        //
        // if (tier == 0) {
        //   console2.log(
        //     "+++++++++++++++++++++ $ Claiming Grand prize of ",
        //     prizePool.getTierPrizeSize(0)
        //   );
        // }

        uint feesForBatch = claimer.claimPrizes(
          vault,
          tier,
          winners,
          prizeIndices,
          address(this),
          0
        );

        totalFeesForBatch += feesForBatch;

        logClaimerToCsv(
          claimerCsvFile,
          RawClaimerLog({
            drawId: drawId,
            tier: tier,
            winners: winners,
            prizeIndices: prizeIndices,
            feesForBatch: feesForBatch
          })
        );

        if (tier != (prizePool.numberOfTiers() - 1)) {
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

  function countContiguousTierPrizes(
    uint _nextPrizeIndex,
    uint _claimCount
  ) public view returns (uint8 tier, uint256 count) {
    uint256 prizeCount;
    bool init = false;
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

  function countWinners(
    uint _nextPrizeIndex,
    uint _claimCount
  ) public view returns (uint256 count) {
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
    uint256 drawId = prizePool.getLastAwardedDrawId();
    require(drawId >= computedDrawId, "invalid draw");
    uint8 numTiers = prizePool.numberOfTiers();
    drawNumberOfTiers[drawId] = numTiers;
    for (uint8 t = 0; t < numTiers; t++) {
      // make sure canary tier is last
      for (uint i = 0; i < env.userCount(); i++) {
        address user = env.users(i);
        for (uint32 p = 0; p < prizePool.getTierPrizeCount(t); p++) {
          if (prizePool.isWinner(address(vault), user, t, p)) {
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

    if (isLogging(2)) {
      console2.log(
        "+++++++++++++++++++++ Prize Claim Cost (cents):",
        (gasConfig.gasUsagePerClaim * gasConfig.gasPriceInPrizeTokens) / 1e16
      );
      console2.log(
        "+++++++++++++++++++++ Draw",
        drawId,
        "has winners: ",
        drawPrizes[drawId].length
      );
      console2.log(
        "+++++++++++++++++++++ Draw",
        drawId,
        "has tiers (inc. canary): ",
        prizePool.numberOfTiers()
      );
      console2.log("+++++++++++++++++++++ Expected Prize Count", prizePool.estimatedPrizeCount());

      for (uint8 t = 0; t < prizePool.numberOfTiers(); t++) {
        uint prizeSize = prizePool.getTierPrizeSize(t) / 1e16;
        console2.log("\t\t\tTier", t);
        console2.log(
          "\t\t\t\tprize size (cents): ",
          prizeSize,
          "prize count: ",
          countTierPrizes(t)
        );
      }
      console2.log("\t\t\tReserve", prizePool.reserve() / 1e18);
    }
  }
}
