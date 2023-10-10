// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { Config } from "../utils/Config.sol";
import { Constant } from "../utils/Constant.sol";

abstract contract BaseEnvironment is Config, Constant, CommonBase, StdCheats {}
