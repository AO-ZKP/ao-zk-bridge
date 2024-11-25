import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { ArweaveWalletKit } from "arweave-wallet-kit";
import App from "./App.tsx";
import "@/styles/globals.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ArweaveWalletKit
      config={{
        permissions: ["ACCESS_ADDRESS", "SIGN_TRANSACTION"],
        ensurePermissions: true,
      }}
    >
      <App />
    </ArweaveWalletKit>
  </StrictMode>
);
