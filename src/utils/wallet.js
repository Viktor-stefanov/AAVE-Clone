import { ethers } from "ethers";

export default {
  accounts: [],
  account: null,
  balance: null,
  network: {},
  walletConnected: false,

  connectWallet: async function connectWallet() {
    if (window.ethereum) {
      try {
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        const { chainId, name } = await provider.getNetwork();
        this.walletConnected = true;
        this.accounts = await provider.send("eth_requestAccounts", []);
        this.account = this.accounts[0];
        this.network = { name, chainId };
        this.balance = ethers.utils.formatEther(await provider.getBalance(this.account));
        return true;
      } catch (err) {
        console.log(err);
        return false;
      }
    } else return false;
  },

  getData: function getData() {
    return {
      networkName: this.network.name,
      chainId: this.network.chainId,
      account: this.account,
      accounts: this.accounts,
      balance: this.balance,
      walletConnected: this.walletConnected,
    };
  },
};
