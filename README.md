# PoolTogether V5 Simulator

This project simulates PoolTogether V5 in a configurable environment.

## Usage

Run the environment scripts:

```
./scripts/optimism.sh
./scripts/ethereum.sh
```

These scripts run the SingleChain test using the `config/optimism.json` and `config/ethereum.json` config files, respectively. They output to `config/output/optimism-output.csv` and `config/output/ethereum-output.csv`.

### Configuration and Output

The simulator is configured using JSON files in the config directory. The simulation outputs results to a CSV file.

To run the simulation for a certain config and output:

```
CONFIG=config/optimism.json OUTPUT=config/optimism-output.csv forge test -vv --mt testSingleChain
```

There are also bash scripts that can be run as a shortcut:

`./scripts/optimism.sh`

## Development

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [direnv](https://direnv.net/) to handle environment variables
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report

Install dependencies:

```
npm i
```

### Env

Copy `.envrc.example` and write down the env variables needed to run this project.

```
cp .envrc.example .envrc
```

Once your env variables are setup, load them with:

```
direnv allow
```

### Compile

Run the following command to compile the contracts:

```
npm run compile
```

### Coverage

Forge is used for coverage, run it with:

```
npm run coverage
```

You can then consult the report by opening `coverage/index.html`:

```
open coverage/index.html
```

### Code quality

[Husky](https://typicode.github.io/husky/#/) is used to run [lint-staged](https://github.com/okonet/lint-staged) and tests when committing.

[Prettier](https://prettier.io) is used to format TypeScript and Solidity code. Use it by running:

```
npm run format
```

[Solhint](https://protofire.github.io/solhint/) is used to lint Solidity files. Run it with:

```
npm run hint
```

### CI

A default Github Actions workflow is setup to execute on push and pull request.

It will build the contracts and run the test coverage.

You can modify it here: [.github/workflows/coverage.yml](.github/workflows/coverage.yml)

For the coverage to work, you will need to setup the `MAINNET_RPC_URL` repository secret in the settings of your Github repository.
