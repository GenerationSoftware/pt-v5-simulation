// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import "forge-std/Test.sol";

import { Environment, PrizePool, Vault, GasConfig, Claimer } from "src/Environment.sol";
import { ClaimerAgent } from "src/ClaimerAgent.sol";

contract ClaimerAgentTest is Test {

    Environment env = Environment(address(0xffff1));
    PrizePool prizePool = PrizePool(address(0xffff2));
    Vault vault = Vault(address(0xffff5));
    Claimer claimer = Claimer(address(0xffff6));

    address user1 = address(0xffff3);
    address user2 = address(0xffff4);
    
    ClaimerAgent agent;

    uint numTiers = 2;

    function setUp() public {
        vm.etch(address(env), "environment");
        vm.etch(address(prizePool), "prizePool");
        vm.etch(address(vault), "vault");
        vm.etch(address(claimer), "claimer");

        GasConfig memory gasConfig = GasConfig({
            gasPriceInPrizeTokens: 90000 gwei,
            gasUsagePerClaim: 150_000,
            gasUsagePerLiquidation: 500_000,
            gasUsagePerStartDraw: 100_000,
            gasUsagePerCompleteDraw: 100_000,
            gasUsagePerDispatchDraw: 100_000
        });

        vm.mockCall(address(env), abi.encodeWithSignature("prizePool()"), abi.encode(address(prizePool)));
        vm.mockCall(address(env), abi.encodeWithSignature("vault()"), abi.encode(address(vault)));
        vm.mockCall(address(env), abi.encodeWithSignature("claimer()"), abi.encode(address(claimer)));
        vm.mockCall(address(env), abi.encodeWithSelector(Environment.userCount.selector), abi.encode(2));
        vm.mockCall(address(env), abi.encodeWithSignature("users(uint256)", 0), abi.encode(user1));
        vm.mockCall(address(env), abi.encodeWithSignature("users(uint256)", 1), abi.encode(user2));
        vm.mockCall(address(env), abi.encodeWithSignature("gasConfig()"), abi.encode(gasConfig));

        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.getTierPrizeCount.selector, 0), abi.encode(1));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.getTierPrizeCount.selector, 1), abi.encode(4));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(prizePool.getLastCompletedDrawId.selector), abi.encode(1));
        vm.mockCall(address(prizePool), abi.encodeWithSignature("numberOfTiers()"), abi.encode(numTiers));

        mockNoPrizes(user1, numTiers);
        mockNoPrizes(user2, numTiers);

        agent = new ClaimerAgent(env);
    }

    function testComputePrizes_noPrizes() public {
        agent.computePrizes();

        assertEq(agent.computedDrawId(), 1);
        assertEq(agent.getPrizeCount(1), 0);
    }

    function testComputePrizes_one_prize() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));

        agent.computePrizes();

        assertEq(agent.computedDrawId(), 1);
        assertEq(agent.getPrizeCount(1), 1);
    }

    function testComputePrizes_four_prizes() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 0), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 3), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user2, 1, 2), abi.encode(true));

        agent.computePrizes();

        assertEq(agent.computedDrawId(), 1);
        assertEq(agent.getPrizeCount(1), 4);
    }

    function testCountContiguousTierPrizes() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 0, 0), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 3), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user2, 1, 2), abi.encode(true));

        agent.computePrizes();

        uint8 tier;
        uint256 prizeCount;

        (tier, prizeCount) = agent.countContiguousTierPrizes(0, 2);
        assertEq(tier, 0);
        assertEq(prizeCount, 1);

        (tier, prizeCount) = agent.countContiguousTierPrizes(1, 2);
        assertEq(tier, 1);
        assertEq(prizeCount, 2);

        (tier, prizeCount) = agent.countContiguousTierPrizes(1, 3);
        assertEq(tier, 1);
        assertEq(prizeCount, 3);
    }

    function testCountWinners() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 0, 0), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 3), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user2, 1, 2), abi.encode(true));

        agent.computePrizes();

        assertEq(agent.countWinners(1, 2), 1, "skip the first");
        assertEq(agent.countWinners(1, 3), 2, "skip the first span two");
    }

    function testCountPrizeIndicesPerWinner() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 0, 0), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 3), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user2, 1, 2), abi.encode(true));

        agent.computePrizes();

        uint32[] memory indices;
        
        indices = agent.countPrizeIndicesPerWinner(1, 3, 2);
        assertEq(indices.length, 2);
        assertEq(indices[0], 2);
        assertEq(indices[1], 1);
    }

    function testPopulateArrays() public {
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 0, 0), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 1), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user1, 1, 3), abi.encode(true));
        vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user2, 1, 2), abi.encode(true));

        agent.computePrizes();

        address[] memory winners;
        uint32[][] memory winnerPrizeIndices;

        uint32[] memory indices;

        indices = new uint32[](1);
        indices[0] = 1;
        (winners, winnerPrizeIndices) = agent.populateArrays(0, 1, 1, indices);
        assertEq(winners.length, 1);
        assertEq(winners[0], user1);
        assertEq(winnerPrizeIndices.length, 1);
        assertEq(winnerPrizeIndices[0].length, 1);
        assertEq(winnerPrizeIndices[0][0], 0);

        indices = new uint32[](2);
        indices[0] = 2;
        indices[1] = 1;
        (winners, winnerPrizeIndices) = agent.populateArrays(1, 3, 2, indices);
        assertEq(winners.length, 2);
        assertEq(winners[0], user1);
        assertEq(winners[1], user2);
        assertEq(winnerPrizeIndices.length, 2);
        assertEq(winnerPrizeIndices[0].length, 2);
        assertEq(winnerPrizeIndices[1].length, 1);
        assertEq(winnerPrizeIndices[0][0], 1);
        assertEq(winnerPrizeIndices[0][1], 3);
        assertEq(winnerPrizeIndices[1][0], 2);
    }

    function mockNoPrizes(address user, uint numTiers) public {
        for (uint t = 0; t < numTiers; t++) {
            for (uint p = 0; p < 4**t; p++) {
                vm.mockCall(address(prizePool), abi.encodeWithSelector(PrizePool.isWinner.selector, address(vault), user, t, p), abi.encode(false));
                // console.log("mocked", user, t, p);
            }
        }
    }

}
