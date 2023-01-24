import { useEffect, useState } from "react";
import Header from "./Header";
import {
  getAllActivePoolAssetNames,
  getPoolDepositData,
  deposit,
  redeem,
} from "../utils/contracts";

export default function LendingPage() {
  const [useAsCollateral, setUseAsCollateral] = useState(false);
  const [depositAmount, setDepositAmount] = useState(null);
  const [redeemAmount, setRedeemAmount] = useState("");
  const [yieldEstimate, setYieldEstimate] = useState(null);
  const [marketData, setMarketData] = useState(null);
  const [markets, setMarkets] = useState([]);

  useEffect(() => {
    async function getMarkets() {
      setMarkets(await getAllActivePoolAssetNames());
    }
    getMarkets();
  }, []);

  function onDepositAmountInput(amount, apy) {
    if (isNaN(amount)) setDepositAmount(null);
    else {
      setDepositAmount(amount);
      setYieldEstimate(amount + amount * (apy / 100));
    }
  }

  async function depositFunds() {
    await deposit(marketData.asset, depositAmount, useAsCollateral);
  }

  async function redeemDeposit() {
    await redeem(marketData.asset, redeemAmount);
  }

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
            You have deposited {marketData.userDepositedLiquidity}{" "}
            {marketData.asset} in this pool
          </p>
          {marketData.userDepositedLiquidity > 0 && (
            <>
              <span>Enter the amount you wish to redeem: </span>
              <input
                value={redeemAmount}
                disabled={redeemAmount === marketData.userMaxRedeemAmount}
                type="number"
                onInput={(e) => setRedeemAmount(e.target.value)}
              />
              <br />
              <span>
                Redeem maximal amount {marketData.userMaxRedeemAmount}{" "}
                {marketData.asset}?
              </span>
              <input
                type="checkbox"
                onChange={(e) =>
                  e.target.checked
                    ? setRedeemAmount(marketData.userMaxRedeemAmount)
                    : setRedeemAmount("")
                }
              />
              <br />
              {redeemAmount && <button onClick={redeemDeposit}>Redeem</button>}
            </>
          )}
          <p>
            Total borrowed liquidity: {marketData.borrowedLiquidity}{" "}
            {marketData.asset}
          </p>
          <p>Loan To Value (LTV): {marketData.loanToValue}%</p>
          <p>
            Expected APY (this number will vary with the amount of
            borrowed/deposited assets):{" "}
            {marketData.depositAPY === 0 ? "N/A" : `${marketData.depositAPY}%`}
          </p>
          <span>
            Enter the amount of {marketData.asset} that you wish to deposit:{" "}
          </span>
          <input
            type="number"
            onInput={(e) =>
              onDepositAmountInput(
                parseFloat(e.target.value),
                marketData.depositAPY
              )
            }
          />
          <br />
          <span>Use asset as collateral? </span>
          <input
            onChange={(e) => setUseAsCollateral(e.target.checked)}
            type="checkbox"
          />
          {depositAmount && (
            <>
              {useAsCollateral ? (
                <br />
              ) : (
                <p>
                  Estimated yield after 1 year: {yieldEstimate}{" "}
                  {marketData.asset}{" "}
                </p>
              )}
              <button onClick={depositFunds}>Deposit</button>
            </>
          )}
        </div>
      )}
    </>
  );
}
