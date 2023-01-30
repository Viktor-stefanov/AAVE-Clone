import { useState, useContext, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import AuthContext from "./AuthContext";

export default function LoginPage() {
  const [loggingIn, setLoggingIn] = useState(null);
  const { walletData, onLogin } = useContext(AuthContext);
  const navigate = useNavigate();

  useEffect(() => {
    if (walletData.walletConnected) navigate("/");
  }, [walletData.walletConnected]);

  async function handleLogin() {
    setLoggingIn(true);
    await onLogin();
    setLoggingIn(false);
  }

  return (
    <>
      <h2>AAVE(v1) Market</h2>
      <button onClick={handleLogin} disabled={loggingIn}>
        Connect Metamask
      </button>
      {loggingIn && <p>Waiting...</p>}
    </>
  );
}
