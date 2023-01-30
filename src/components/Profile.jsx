import Header from "./Header";
import { utils } from "ethers";
import { useEffect, useState } from "react";
import {
  getRepayAndCollateralOnLiquidation,
  getUserCollateralBalance,
  getUserGlobalData,
  getUserPoolData,
  liquidationCall,
} from "../utils/contracts";

export default function Profile() {
  const [userData, setUserData] = useState([]);
  const [poolToRepay, setPoolToRepay] = useState(null);
  const [userBorrowBalance, setUserBorrowBalance] = useState(null);
  const [userToLiquidate, setUserToLiquidate] = useState(null);
  const [userCollateralBalance, setUserCollateralBalance] = useState(null);
  const [poolToLiquidate, setPoolToLiquidate] = useState(null);
  const [maxAmountToRepay, setMaxAmountToRepay] = useState(null);
  const [collateralToReceive, setCollateralToReceive] = useState(null);

  useEffect(() => {
    async function loadUserData() {
      setUserData(await getUserGlobalData());
    }
    loadUserData();
  }, []);

  async function onUserToLiquidateInput(address) {
    const isValidAddress = utils.isAddress(address);
    setUserToLiquidate(isValidAddress ? address : null);
  }

  async function onPoolToRepayInput(address) {
    const isValidAddress = utils.isAddress(address);
    setPoolToRepay(isValidAddress ? address : null);
    setUserBorrowBalance(
      isValidAddress ? await getUserPoolData(address) : null
    );
  }

  async function onPoolToLiquidateInput(address) {
    const isValidAddress = utils.isAddress(address);
    setPoolToLiquidate(isValidAddress ? address : null);
    const collateralBalance = isValidAddress
      ? await getUserCollateralBalance(address)
      : null;
    setUserCollateralBalance(collateralBalance);
    const [collateralToReceive, maxAmountToRepay] = isValidAddress
      ? await getRepayAndCollateralOnLiquidation(
          poolToRepay,
          address,
          collateralBalance
        )
      : [null, null];
    setMaxAmountToRepay(maxAmountToRepay);
    setCollateralToReceive(collateralToReceive);
  }

  async function liquidateUser() {
    await liquidationCall(
      poolToRepay,
      poolToLiquidate,
      userToLiquidate,
      maxAmountToRepay
    );
  }

  return (
    <>
      <Header />
      <h2>Global data accross all markets</h2>
      <p>Total deposit balance: {userData.totalLiquidityProvided}$</p>
      <p>Total collateral balance: {userData.totalCollateralBalance}$</p>
      <p>Total borrow balance: {userData.totalBorrowBalance}$</p>
      <p>Total fees balance: {userData.totalFees}$</p>
      <p>
        Health factor:{" "}
        {userData.healthFactor > 1000 ? "N/A" : userData.healthFactor}
      </p>
      <p>
        Your borrow positions can
        {userData.healthFactorBelowThreshold ? "" : "not"} be liquidated
      </p>
      <span>Enter the address of the user you wish to liquidate:</span>
      <input
        type="text"
        onInput={(e) => onUserToLiquidateInput(e.target.value)}
      />
      <br />
      <span>Enter the address of the market to repay the loan: </span>
      <input
        type="text"
        disabled={!userToLiquidate}
        onInput={(e) => onPoolToRepayInput(e.target.value)}
      />
      <br />
      <span>Enter the address of the collateral market: </span>
      <input
        type="text"
        disabled={!userToLiquidate || !poolToRepay}
        onInput={(e) => onPoolToLiquidateInput(e.target.value)}
      />
      {maxAmountToRepay && collateralToReceive && (
        <>
          <p>You can liquidate a maximum amount of: {maxAmountToRepay}</p>
          <p>
            You will receive {collateralToReceive} for {maxAmountToRepay}
          </p>
          <button onClick={liquidateUser}>Liquidate User</button>
        </>
      )}
    </>
  );
}
