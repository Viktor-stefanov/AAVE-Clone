import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";
import Wallet from "../utils/wallet";

export default function AuthProvider({ children }) {
  const navigate = useNavigate();

  useEffect(() => {
    const wd = localStorage.getItem("walletData");
    localStorage.setItem("walletData", wd ? wd : "{}");
  }, []);

  async function onLogin() {
    if (await Wallet.connectWallet()) {
      const newWalletData = Wallet.getData();
      localStorage.setItem("walletData", JSON.stringify(newWalletData));
      navigate("/");
    }
  }

  function getWalletData() {
    return JSON.parse(localStorage.getItem("walletData"));
  }

  function onLogout() {
    localStorage.setItem("walletData", "{}");
    navigate("/login", { replace: true });
  }

  const auth = {
    getWalletData,
    onLogin,
    onLogout,
  };

  return <AuthContext.Provider value={auth}>{children}</AuthContext.Provider>;
}
