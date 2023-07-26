//////////////////////////////////////
//
// This script uses Deno (https://deno.land/)
// Run with `deno run --allow-net --allow-write historicPrices.ts`
// Fetches data from CoinGecko API and writes to historicPrices.json
// NOTE: Exchange rate is multiplied by 1e9 for precision. 1e18 results in numbers too large to be parsed in Solidity.
//
//////////////////////////////////////

const poolDeployTime = 1613465549;
const poolAddress = "0x0cec1a9154ff802e7934fc916ed7ca50bde6844e";
const currentTime = Date.now() / 1000;

enum VsCurrencies {
  ETH = "eth",
  USD = "usd",
}
const getHistoricTokenData = (vs_currency: VsCurrencies) =>
  fetch(
    `https://api.coingecko.com/api/v3/coins/ethereum/contract/${poolAddress}/market_chart/range?vs_currency=${vs_currency}&from=${poolDeployTime}&to=${currentTime}`
  );

type RawPriceData = {
  prices: [number, number][];
  market_caps: [number, number][];
  total_volumes: [number, number][];
};

type PriceData = {
  exchangeRate: number;
  timestamp: number;
}[];

const POOL_USD_PRICE_DATA: RawPriceData = await(
  await getHistoricTokenData(VsCurrencies.USD)
).json();
const POOL_ETH_PRICE_DATA: RawPriceData = await(
  await getHistoricTokenData(VsCurrencies.ETH)
).json();

const formatRawPriceData = (data: RawPriceData) => data.prices.reduce((acc, item) => {
  acc.push({
    timestamp: item[0] / 1000, // Convert to seconds
    exchangeRate: Math.round(item[1] * 1e9), // Convert to whole numbers. 1e18 results in numbers too large to be parsed in Solidity.
  });
  return acc
}, [] as PriceData[])

const formattedData: {
  usd: PriceData[];
  eth: PriceData[];
} = {
  usd: formatRawPriceData(POOL_USD_PRICE_DATA),
  eth: formatRawPriceData(POOL_ETH_PRICE_DATA),
};

await Deno.writeTextFile("../config/historicPrices.json", JSON.stringify(formattedData));
