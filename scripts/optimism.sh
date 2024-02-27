#! /usr/local/bin/bash
rm config/optimism-output.csv
CONFIG=config/optimism.json OUTPUT=config/optimism-output.csv forge test -vvv --mt testSingleChain
