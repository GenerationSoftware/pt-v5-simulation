// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { SD59x18 } from "prb-math/SD59x18.sol";

contract SD59x18OverTime {
  struct Rate {
    uint256 timestamp;
    SD59x18 value;
  }

  // time => prize token value in underlying token
  Rate[] public rates;

  function get(uint256 timestamp) public view returns (SD59x18) {
    return rates[_binarySearch(0, rates.length, timestamp)].value;
  }

  function add(uint256 timestamp, SD59x18 value) public {
    if (rates.length > 0) {
      require(
        timestamp > rates[rates.length - 1].timestamp,
        "SD59x18OverTime::add: timestamp must be greater than last timestamp"
      );
    }

    rates.push(Rate({ timestamp: timestamp, value: value }));
  }

  function _binarySearch(
    uint256 left,
    uint256 right,
    uint256 timestamp
  ) internal view returns (uint256) {
    if (left == right || left == right - 1) {
      return left;
    }

    uint256 mid = left + (right - left) / 2;

    if (rates[mid].timestamp == timestamp || left == rates.length - 1) {
      return mid;
    }

    if (rates[mid].timestamp > timestamp) {
      if (left == mid) {
        return mid;
      }

      return _binarySearch(left, mid - 1, timestamp);
    }

    return _binarySearch(mid, right, timestamp);
  }
}
