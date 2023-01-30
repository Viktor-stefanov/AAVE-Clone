import { useEffect, useState } from "react";
import Header from "./Header";
import {
  calculateExpectedBorrowInterestRate,
  getActivePoolsDisplayData,
  borrow,
  repay,
} from "../utils/contracts";

export default function BorrowPage() {
  const [expectedBorrowRate, setExpectedBorrowRate] = useState("");
  const [borrowAmount, setBorrowAmount] = useState(null);
  const [repayAmount, setRepayAmount] = useState("");
  const [rateMode, setRateMode] = useState(null);
  const [markets, setMarkets] = useState([]);
  const [chosenMarket, setChosenMarket] = useState(null);

  useEffect(() => {
    async function test() {
      setMarkets(await getActivePoolsDisplayData());
    }
    test();
  }, []);

  async function onBorrowAmountChange(asset, amount) {
    setChosenMarket(asset);
    setBorrowAmount(amount);
    if (amount == "") amount = 0;

    setExpectedBorrowRate(
      await calculateExpectedBorrowInterestRate(asset, amount)
    );
  }

  async function borrowAssets(asset) {
    await borrow(asset, borrowAmount, parseInt(rateMode));
  }

  async function repayLoan(asset, repayingWholeLoan) {
    await repay(asset, repayAmount, repayingWholeLoan);
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
          {market.userBorrowedLiquidity > 0 && (
            <>
              <p>
                You have borrowed {market.userBorrowedLiquidity} {market.asset}
              </p>
              <span>Enter the amount you wish to repay:</span>
              <input
                value={repayAmount}
                disabled={repayAmount === market.userRepayAmount}
                type="number"
                onInput={(e) =>
                  e.target.value === ""
                    ? setRepayAmount(null)
                    : setRepayAmount(e.target.value)
                }
              />
              <br />
              <span>
                Repay whole loan ({market.userRepayAmount} {market.asset})?
              </span>
              <input
                type="checkbox"
                onChange={(e) =>
                  e.target.checked
                    ? setRepayAmount(market.userRepayAmount)
                    : setRepayAmount("")
                }
              />
              {repayAmount && (
                <button
                  onClick={() =>
                    repayLoan(
                      market.asset,
                      repayAmount === market.userRepayAmount
                    )
                  }
                >
                  Repay
                </button>
              )}
            </>
          )}
          <p>LTV (Loan To Value): {market.loanToValue}%</p>
          <p>Liquidation Threshold: {market.liquidationThreshold}%</p>
          <p>Liquidation Bonus: {market.liquidationBonus}%</p>
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
            onInput={(e) => onBorrowAmountChange(market.asset, e.target.value)}
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
          {expectedBorrowRate && chosenMarket === market.asset && (
            <>
              <p>Expected borrow interest rate: {expectedBorrowRate}%</p>
            </>
          )}
          {borrowAmount && rateMode && chosenMarket === market.asset && (
            <>
              <button onClick={() => borrowAssets(market.asset)}>Borrow</button>
            </>
          )}
        </div>
      ))}
    </>
  );
}
