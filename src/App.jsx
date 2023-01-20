import { Routes, Route, Navigate } from "react-router-dom";
import AuthProvider from "./components/AuthProvider";
import ProtectedRoute from "./components/ProtectedRoute";
import LendingPage from "./components/LendingPage";
import BorrowPage from "./components/BorrowPage";
import LoginPage from "./components/LoginPage";
import Profile from "./components/Profile";
import Header from "./components/Header";

export default function App() {
  return (
    <AuthProvider>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route element={<ProtectedRoute />}>
          <Route path="/dashboard" element={<Header />} />
          <Route path="/borrow" element={<BorrowPage />} />
          <Route path="*" element={<Navigate to="/dashboard" replace />} />
          <Route path="/lend" element={<LendingPage />} />
          <Route path="/profile" element={<Profile />} />
        </Route>
      </Routes>
    </AuthProvider>
  );
}
