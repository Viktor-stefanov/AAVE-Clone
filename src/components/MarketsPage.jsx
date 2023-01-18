import { useEffect, useState } from "react";
import Header from "./Header";
import { getActivePoolsDisplayData } from "../utils/contracts";

export default function MarketsPage() {
  const [markets, setMarkets] = useState([]);

  useEffect(() => {
    async function test() {
      setMarkets(await getActivePoolsDisplayData());
    }
    test();
  }, []);

  return (
    <>
      <Header />

      <h2>All Active Markets</h2>
      {markets.map((market, index) => (
        <div
          key={index}
          style={{
            float: "left",
            border: "solid black 1px",
            margin: "0 10px 0 10px",
            padding: "5px",
          }}
        >
          <h3>Market: {market.asset} </h3>
          <p>
            Total deposited assets: {market.providedLiquidity} {market.asset}
          </p>
          <p>
            Total borrowed assets: {market.borrowedLiquidity} {market.asset}
          </p>
          <p>LTV (Loan To Value): {market.loanToValue}%</p>
          <p>Liquidation Threshold: {market.liquidationThreshold}%</p>
          <p>Liquidation Bonus: {market.liquidationBonus}%</p>
          <p>This pools is {market.isActive ? "" : "not"} active</p>
          <p>
            Borrowing for this pool is {market.isBorrowingEnabled ? "" : "not "}
            enabled
          </p>
          <p>
            This pool is {market.isUsableAsCollateral ? "" : "not"} usable as
            collateral
          </p>
        </div>
      ))}
    </>
  );
}
