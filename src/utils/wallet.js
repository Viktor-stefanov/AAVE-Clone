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

        await this.addEventListeners(provider);
        return true;
      } catch (err) {
        console.log(err);
        return false;
      }
    } else return false;
  },

  addEventListeners: async function (provider) {
    window.ethereum.on("accountsChanged", async (accounts) => {
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
  },

  isLoggedIn: async function () {
    if (window.ethereum) {
      const provider = new ethers.providers.Web3Provider(
        window.ethereum,
        "any"
      );
      if ((await provider.listAccounts()).length > 0) {
        await this.addEventListeners(provider);
        return true;
      }
      return false;
    }
    return false;
  },

  setData: function (other) {
    this.chainId = other.chainId;
    this.account = other.account;
    this.accounts = other.accounts;
    this.balance = other.balance;
    this.walletConnected = other.walletConnected;
  },

  getData: function () {
    return {
      chainId: this.chainId,
      account: this.account,
      accounts: this.accounts,
      balance: this.balance,
      walletConnected: this.walletConnected,
    };
  },
};
