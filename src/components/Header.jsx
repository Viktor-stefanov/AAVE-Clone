import { useContext } from "react";
import { useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";

export default function Header() {
  const { walletData, onLogout } = useContext(AuthContext);
  const navigate = useNavigate();

  return (
    <>
      <span>Account: {walletData.account} | </span>
      <span>Balance: {walletData.balance} ETH | </span>
      <span>Chain ID: {walletData.chainId} | </span>
      <button onClick={onLogout}>Log Out</button>
      <br />

      {walletData.chainId === 31337 ? (
        <>
          <button onClick={() => navigate("/borrow", { replace: true })}>
            Borrow
          </button>
          <button onClick={() => navigate("/lend", { replace: true })}>
            Lend
          </button>
          <button onClick={() => navigate("/profile", { replace: true })}>
            Profile
          </button>
        </>
      ) : (
        <>
          <h2>Please change your network to hardhat local :)</h2>
        </>
      )}
    </>
  );
}
