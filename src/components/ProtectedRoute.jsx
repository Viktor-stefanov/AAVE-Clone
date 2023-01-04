import { useContext, useEffect } from "react";
import { Outlet, useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";

export default function ProtectedRoute() {
  const { getWalletData } = useContext(AuthContext);
  const navigate = useNavigate();

  useEffect(() => {
    if (!getWalletData().walletConnected) navigate("/login");
  }, []);

  return <Outlet />;
}
