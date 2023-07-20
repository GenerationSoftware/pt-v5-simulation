//////////////////////////////////////
//
// This script uses Deno (https://deno.land/)
// Run with `deno run --allow-all formatSimulatorEvents.ts`
// Formats generated events from the simulator test.
//
//////////////////////////////////////

import ERC20 from '../out/ERC20.sol/ERC20.json' assert { type: "json" };
import Claimer from '../out/Claimer.sol/Claimer.json' assert { type: "json" };
import ContinuousGDA from '../out/ContinuousGDA.sol/ContinuousGDA.json' assert { type: "json" };
import DrawAccumulatorLib from '../out/DrawAccumulatorLib.sol/DrawAccumulatorLib.json' assert { type: "json" };
import DrawAuction from '../out/DrawAuction.sol/DrawAuction.json' assert { type: "json" };
import ERC4626 from '../out/ERC4626.sol/ERC4626.json' assert { type: "json" };
import PrizePool from '../out/PrizePool.sol/PrizePool.json' assert { type: "json" };
import TieredLiquidityDistributor from '../out/TieredLiquidityDistributor.sol/TieredLiquidityDistributor.json' assert { type: "json" };
import TwabController from '../out/TwabController.sol/TwabController.json' assert { type: "json" };
import Vault from '../out/Vault.sol/Vault.json' assert { type: "json" };
import VaultFactory from '../out/VaultFactory.sol/VaultFactory.json' assert { type: "json" };

import { decodeEventLog } from 'npm:viem'

const RAW_EVENTS = (await Deno.readTextFile("../data/rawEventsOut.csv")).split("\n").slice(1, -1).map((row) => (row.split(",")));

// NOTE: Missing event with signature hash: 0xc31bc4fb7f1c35cfd7aa34780f09c3f0a97653a70920593b2284de94a4772957
const superAbi = [ERC20,
	Claimer,
	ContinuousGDA,
	DrawAccumulatorLib,
	DrawAuction,
	ERC4626,
	PrizePool,
	TieredLiquidityDistributor,
	TwabController,
	Vault,
	VaultFactory].flatMap(({abi}) => abi.filter(({type}) => type === "event"))

const formattedData: {
	eventNumber: number;
	data: string
	emitter: string
	topics: string[]
}[] = RAW_EVENTS.map((row) => {
	const eventNumber = Number(row[0]);
	const emitter = row[1];
	const data = row[2];
	const topics = [
		row[3],
		row[4],
		row[5],
	]
	return {
		eventNumber,
		data,
		emitter,
		topics,
	}
})

const finalEvents = []
formattedData.forEach((event) => {
	try {
		finalEvents.push(decodeEventLog({
			abi: superAbi,
			data: event.data,
			topics: event.topics,
			strict: false 
		}))
	} catch (e) {
		console.log("Error decoding event: ", event.topics[0])
	}
})


await Deno.writeTextFile(
	"../data/simulatorEvents.json",
	// JSON.stringify(finalEvents)
	JSON.stringify(finalEvents, (key, value) =>
            typeof value === 'bigint'
                ? value.toString()
                : value
        )
);


