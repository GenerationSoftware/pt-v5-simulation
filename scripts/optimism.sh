#! /usr/local/bin/bash
rm config/output/optimism-output.csv
CONFIG=config/optimism.json OUTPUT=config/output/optimism-output.csv forge test -vvv --mt testSingleChain
