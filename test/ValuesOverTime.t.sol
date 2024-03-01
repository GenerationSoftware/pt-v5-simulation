// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { SD59x18OverTime, SD59x18 } from "../src/utils/SD59x18OverTime.sol";

contract SD59x18OverTimeTest is Test {
  SD59x18OverTime rates;

  function setUp() public {
    rates = new SD59x18OverTime();

    rates.add(1 days, SD59x18.wrap(10e18));
    rates.add(2 days, SD59x18.wrap(100e18));
    rates.add(8 days, SD59x18.wrap(1000e18));
  }

  function testGet_onFirst() public {
    assertEq(SD59x18.unwrap(rates.get(1 days)), 10e18, "match first timestamp");
  }

  function testGet_afterFirst() public {
    assertEq(SD59x18.unwrap(rates.get(1.5 days)), 10e18, "just after first timestamp");
  }

  function testGet_onSecond() public {
    assertEq(SD59x18.unwrap(rates.get(2 days)), 100e18, "match second timestamp");
  }

  function testGet_afterSecond() public {
    assertEq(SD59x18.unwrap(rates.get(2.5 days)), 100e18, "just after second timestamp");
  }

  function testGet_onThird() public {
    assertEq(SD59x18.unwrap(rates.get(8 days)), 1000e18, "match third timestamp");
  }

  function testGet_afterThird() public {
    assertEq(SD59x18.unwrap(rates.get(8.5 days)), 1000e18, "just after third timestamp");
  }

  function testGet_regression() public {
    uint256 startTime = 34560001;
    rates = new SD59x18OverTime();
    rates.add(0, SD59x18.wrap(1e18));
    rates.add(startTime + 2 days, SD59x18.wrap(10e18));
    rates.add(startTime + 3 days, SD59x18.wrap(100e18));
    rates.add(startTime + 4 days, SD59x18.wrap(1000e18));

    assertEq(SD59x18.unwrap(rates.get(34560001)), 1e18, "match first timestamp");
  }
}
