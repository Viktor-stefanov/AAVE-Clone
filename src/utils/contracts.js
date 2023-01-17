import { ethers } from "ethers";
import dpJson from "../../deployments/localhost/DataProvider.json";
import diamondJson from "../../deployments/localhost/Diamond.json";

const { dpDiamond } = await instantiateContracts();

async function instantiateContracts() {
  const provider = new ethers.providers.Web3Provider(window.ethereum),
    signer = provider.getSigner(),
    dp = new ethers.Contract(dpJson.address, dpJson.abi, signer),
    dpDiamond = new ethers.Contract(diamondJson.address, dpJson.abi, signer);

  return { dpDiamond };
}

async function getAllActivePools() {
  return await dpDiamond.getAllActivePools();
}

export { getAllActivePools };
