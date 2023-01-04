import { useContext } from "react";
import { useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";

export default function Header() {
  const { getWalletData, onLogout } = useContext(AuthContext);
  const navigate = useNavigate();
  const walletData = getWalletData();

  return (
    <>
      <span>Account: {walletData.account} | </span>
      <span>Balance: {walletData.balance} ETH | </span>
      <span>Chain ID: {walletData.chainId} | </span>
      <button onClick={onLogout}>Log Out</button>
      <br />

      <button onClick={() => navigate("/markets", { replace: true })}>Markets</button>
      <button onClick={() => navigate("/lend", { replace: true })}>Lend</button>
    </>
  );
}
