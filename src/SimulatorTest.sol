// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { Vm, VmSafe } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

abstract contract SimulatorTest is Test {
  modifier recordEvents() {
    string memory filePath = string.concat(vm.projectRoot(), "/data/rawEventsOut.csv");
    vm.writeFile(filePath, "");
    vm.writeLine(filePath, "Event Number, Emitter, Data, Topic 0, Topic 1, Topic 2, Topic 3,");
    vm.recordLogs();

    _;

    Vm.Log[] memory entries = vm.getRecordedLogs();

    for (uint i = 0; i < entries.length; i++) {
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

      for (uint j = 0; j < log.topics.length; ++j) {
        row = string.concat(row, vm.toString(log.topics[j]), ",");
      }
      for (uint j = log.topics.length - 1; j < 4; ++j) {
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
