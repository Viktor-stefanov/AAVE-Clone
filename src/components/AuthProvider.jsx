import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";
import Wallet from "../utils/wallet";

export default function AuthProvider({ children }) {
  const [walletData, setWalletData] = useState({});
  const navigate = useNavigate();

  useEffect(() => {
    const wd = localStorage.getItem("walletData");
    setWalletData(JSON.parse(wd));
    localStorage.setItem("walletData", wd ? wd : "{}");
  }, []);

  async function storeWalletData() {
    const newWalletData = Wallet.getData();
    localStorage.setItem("walletData", JSON.stringify(newWalletData));
    setWalletData(newWalletData);
  }

  async function onLogin() {
    if (await Wallet.connectWallet()) {
      window.ethereum.on("change", () => storeWalletData()); //storeWalletData);
      storeWalletData();
      navigate("/");
    }
  }

  function onLogout() {
    setWalletData({});
    localStorage.setItem("walletData", "{}");
    navigate("/login", { replace: true });
  }

  const auth = {
    walletData,
    onLogin,
    onLogout,
  };

  return <AuthContext.Provider value={auth}>{children}</AuthContext.Provider>;
}
