import { Routes, Route, Navigate } from "react-router-dom";
import AuthProvider from "./components/AuthProvider";
import ProtectedRoute from "./components/ProtectedRoute";
import LendingPage from "./components/LendingPage";
import MarketsPage from "./components/MarketsPage";
import LoginPage from "./components/LoginPage";
import Header from "./components/Header";

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<ProtectedRoute />}>
          <Route path="/dashboard" element={<Header />} />
          <Route path="/markets" element={<MarketsPage />} />
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
          <Route path="/lend" element={<LendingPage />} />
        </Route>
      </Routes>
    </AuthProvider>
  );
}
