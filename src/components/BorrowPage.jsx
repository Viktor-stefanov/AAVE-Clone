import { ethers } from "ethers";
import { useEffect, useState } from "react";
import Header from "./Header";
import { getActivePoolsDisplayData, borrow, repay } from "../utils/contracts";

export default function BorrowPage() {
  const [borrowAmount, setBorrowAmount] = useState(null);
  const [repayAmount, setRepayAmount] = useState(null);
  const [rateMode, setRateMode] = useState(null);
  const [markets, setMarkets] = useState([]);

  useEffect(() => {
    async function test() {
      setMarkets(await getActivePoolsDisplayData());
    }
    test();
  }, []);

  async function borrowAssets(asset) {
    await borrow(asset, borrowAmount, parseInt(rateMode));
  }

  async function repayLoan(asset) {
    await repay(asset, repayAmount);
  }

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
          <p>
            You have borrowed {market.userBorrowedLiquidity} {market.asset}
          </p>
          {market.userBorrowedLiquidity > 0 && (
            <>
              <span>Enter the amount you wish to repay:</span>
              <input
                type="number"
                onInput={(e) =>
                  e.target.value === ""
                    ? setRepayAmount(null)
                    : setRepayAmount(ethers.utils.parseEther(e.target.value))
                }
              />
              <br />
              <span>
                Total repay amount: {market.userRepayAmount} {market.asset}
              </span>
              {repayAmount && (
                <button onClick={() => repayLoan(market.asset)}>Repay</button>
              )}
            </>
          )}
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
          <span>
            Enter the amount of {market.asset} that you wish to borrow:{" "}
          </span>
          <input
            type="number"
            onInput={(e) => setBorrowAmount(parseFloat(e.target.value))}
          />
          <br />
          <span>Select your desired interest rate mode: </span>
          <select
            defaultValue="init"
            onInput={(e) => setRateMode(e.target.value)}
          >
            <option value="init" disabled></option>
            <option value="0">variable</option>
            <option value="1">stable</option>
          </select>
          <br />
          {borrowAmount && rateMode && (
            <>
              <button onClick={() => borrowAssets(market.asset)}>Borrow</button>
            </>
          )}
        </div>
      ))}
    </>
  );
}
