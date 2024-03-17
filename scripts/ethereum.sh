#!/usr/bin/env bash
rm config/output/ethereum-output.csv
CONFIG=config/ethereum.json OUTPUT=config/output/ethereum-output.csv forge test -vvv --mt testSingleChain
