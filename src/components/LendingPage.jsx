// target: 2.442011765253355%
import { useEffect, useState } from "react";
import Header from "./Header";
import {
  getAllActivePoolAssetNames,
  getPoolDepositData,
} from "../utils/contracts";

export default function LendingPage() {
  const [marketData, setMarketData] = useState(null);
  const [markets, setMarkets] = useState([]);

  useEffect(() => {
    async function getMarkets() {
      setMarkets(await getAllActivePoolAssetNames());
    }
    getMarkets();
  }, []);

  return (
    <>
      <Header />

      <br />
      <br />
      <span>
        Select the asset you wish to deposit and generate a yield upon:{" "}
      </span>
      <select
        defaultValue="init"
        onChange={async (e) => {
          setMarketData(await getPoolDepositData(e.currentTarget.value));
        }}
      >
        <option value="init" disabled></option>
        {markets.map((asset, index) => (
          <option value={asset} key={index}>
            {asset}
          </option>
        ))}
      </select>
      <br />
      <br />

      {marketData && (
        <div
          style={{
            float: "left",
            border: "solid black 1px",
            margin: "0 10px 0 10px",
            padding: "5px",
          }}
        >
          <p>Market: {marketData.asset}</p>
          <p>
            Total deposited liquidity: {marketData.depositedLiquidity}{" "}
            {marketData.asset}
          </p>
          <p>
            Total borrowed liquidity: {marketData.borrowedLiquidity}{" "}
            {marketData.asset}
          </p>
          <p>Current overall borrow rate: {marketData.overallBorrowRate}</p>
          <p>Current liquidity rate: {marketData.currentLiquidityRate}</p>
          <p>
            Expected APY (this number will vary with the amount of
            borrowed/deposited assets):{" "}
            {marketData.depositAPY === 0 ? "N/A" : marketData.depositAPY}
          </p>
        </div>
      )}
    </>
  );
}
