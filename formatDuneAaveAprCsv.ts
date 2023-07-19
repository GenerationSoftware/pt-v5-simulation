//////////////////////////////////////
//
// This script uses Deno (https://deno.land/)
// Run with `deno run --allow-all formatDuneAaveAprCsv.ts`
// Formats downloaded APR data from Dune Analytics.
// https://dune.com/queries/2745242?blockchain=ethereum&category=abstraction&namespace=aave&table=interest&blockchains=ethereum
// NOTE: APR is multiplied by 1e18 for precision.
//
//////////////////////////////////////

const USDC_APR_DATA = (await Deno.readTextFile("./USDC.csv")).split("\n");
const WETH_APR_DATA = (await Deno.readTextFile("./WETH.csv")).split("\n");

type AprData = {
  timestamp: string;
  apr: number;
};

const formatRawAprData = (aprData: any) =>
  aprData.reduce((acc, rowData) => {
    if (!rowData) return acc;
    acc.push({
      timestamp: new Date(rowData.split(",")[2]).getTime() / 1000, // Convert to epoch seconds
      apr: Math.round(Number(rowData.split(",")[1]) * 1e18), // Convert to wei
    });
    return acc;
  }, [] as AprData[]);

const formattedData: {
  usd: AprData[];
  eth: AprData[];
} = {
  usd: formatRawAprData(USDC_APR_DATA.slice(1)),
  eth: formatRawAprData(WETH_APR_DATA.slice(1)),
};

await Deno.writeTextFile(
  "./data/historicAaveApr.json",
  JSON.stringify(formattedData)
);
