// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { BaseEnvironment } from "../environment/Base.sol";

contract EthereumEnvironment is BaseEnvironment {
  constructor(
    PrizePoolConfig memory _prizePoolConfig,
    RngAuctionConfig memory _rngAuctionConfig
  ) BaseEnvironment(_prizePoolConfig, _rngAuctionConfig) {}
}
