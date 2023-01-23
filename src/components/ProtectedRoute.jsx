import { useContext, useEffect } from "react";
import { Outlet, useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";

export default function ProtectedRoute() {
  const { walletData } = useContext(AuthContext);
  const navigate = useNavigate();

  useEffect(() => {
    if (!walletData.walletConnected) navigate("/login");
  }, []);

  return <Outlet />;
}
