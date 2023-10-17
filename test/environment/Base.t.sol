// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { Config } from "../../src/utils/Config.sol";
import { Constant } from "../../src/utils/Constant.sol";
import { Utils } from "../../src/utils/Utils.sol";

import { UintOverTime } from "../utils/UintOverTime.sol";

contract BaseTest is CommonBase, Config, Constant, StdCheats, Test, Utils {
  UintOverTime public aprOverTime;

  // NOTE: Order matters for ABI decode.
  struct HistoricApr {
    uint256 apr;
    uint256 timestamp;
  }

  constructor() {}

  function setUpApr(uint256 _startTime) public {
    aprOverTime = new UintOverTime();

    // Realistic test case
    aprOverTime.add(_startTime, Constant.SIMPLE_APR);
  }

  function setUpAprFromJson(uint256 _startTime) public {
    aprOverTime = new UintOverTime();

    string memory jsonFile = string.concat(vm.projectRoot(), "/config/historicAaveApr.json");
    string memory jsonData = vm.readFile(jsonFile);

    // NOTE: Options for APR are: .usd or .eth
    bytes memory usdData = vm.parseJson(jsonData, "$.usd");
    HistoricApr[] memory aprData = abi.decode(usdData, (HistoricApr[]));

    uint256 initialTimestamp = aprData[0].timestamp;
    for (uint256 i = 0; i < aprData.length; i++) {
      HistoricApr memory rowData = aprData[i];
      aprOverTime.add(_startTime + (rowData.timestamp - initialTimestamp), rowData.apr);
    }
  }

  modifier recordEvents() {
    string memory filePath = string.concat(vm.projectRoot(), "/data/rawEventsOut.csv");
    vm.writeFile(filePath, "");
    vm.writeLine(filePath, "Event Number, Emitter, Data, Topic 0, Topic 1, Topic 2, Topic 3,");
    vm.recordLogs();

    _;

    Vm.Log[] memory entries = vm.getRecordedLogs();

    for (uint256 i = 0; i < entries.length; i++) {
      Vm.Log memory log = entries[i];

      string memory row;
      row = string.concat(
        vm.toString(i),
        ",",
        vm.toString(log.emitter),
        ",",
        vm.toString(log.data),
        ","
      );

      for (uint256 j = 0; j < log.topics.length; ++j) {
        row = string.concat(row, vm.toString(log.topics[j]), ",");
      }
      for (uint256 j = log.topics.length - 1; j < 4; ++j) {
        row = string.concat(row, "0x0,");
      }

      vm.writeLine(filePath, row);
    }

    // NOTE: Takes up way too much memory (it says gas in the log) to parse all of the events in Solidity.

    // string memory rootObj = ".";
    // string memory finalJson;

    // for (uint i = 0; i < entries.length; i++) {
    //   Vm.Log memory log = entries[i];

    //   // Create event object
    //   string memory eventJson;
    //   string memory eventObj = vm.toString(i);
    //   eventJson = vm.serializeAddress(eventObj, "emitter", log.emitter);
    //   eventJson = vm.serializeBytes(eventObj, "data", log.data);

    //   // Create topics object
    //   for (uint j = 0; j < log.topics.length; ++j) {
    //     string memory topicObj = "topics";
    //     string memory topicJson;

    //     topicJson = vm.serializeBytes32(topicObj, vm.toString(j), log.topics[j]);
    //     eventJson = vm.serializeString(eventObj, topicObj, topicJson);
    //   }

    //   finalJson = vm.serializeString(rootObj, vm.toString(i), eventJson);
    // }
    // vm.writeJson(finalJson, filePath);
  }
}
