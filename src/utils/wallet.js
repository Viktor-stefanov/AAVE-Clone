import { ethers } from "ethers";

export default {
  accounts: [],
  account: null,
  balance: null,
  chainId: null,
  walletConnected: false,

  connectWallet: async function connectWallet() {
    if (window.ethereum) {
      try {
        const provider = new ethers.providers.Web3Provider(
          window.ethereum,
          "any"
        );
        const { chainId, name } = await provider.getNetwork();
        this.walletConnected = true;
        this.accounts = await provider.send("eth_requestAccounts", []);
        this.account = this.accounts[0];
        this.chainId = chainId;
        this.balance = ethers.utils.formatEther(
          await provider.getBalance(this.account)
        );

        window.ethereum.on("accountsChanged", async (accounts) => {
          console.log("ACCOUNTS ARE BEING CHANGED");
          this.accounts = accounts;
          this.account = accounts[0];
          this.balance = ethers.utils.formatEther(
            await provider.getBalance(this.account)
          );

          window.ethereum.emit("change");
        });

        window.ethereum.on("chainChanged", async (chainId) => {
          this.balance = ethers.utils.formatEther(
            await provider.getBalance(this.account)
          );
          this.chainId = parseInt(chainId, 16);

          window.ethereum.emit("change");
        });

        return true;
      } catch (err) {
        console.log(err);
        return false;
      }
    } else return false;
  },

  getData: function getData() {
    return {
      chainId: this.chainId,
      account: this.account,
      accounts: this.accounts,
      balance: this.balance,
      walletConnected: this.walletConnected,
    };
  },
};
