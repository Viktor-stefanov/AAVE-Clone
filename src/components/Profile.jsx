import Header from "./Header";
import { useEffect, useState } from "react";
import { getUserGlobalData, redeem, repay } from "../utils/contracts";

export default function Profile() {
  const [userData, setUserData] = useState([]);

  useEffect(() => {
    async function loadUserData() {
      setUserData(await getUserGlobalData());
    }
    loadUserData();
  }, []);

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
    </>
  );
}
