import { ethers } from "ethers";
import dpJson from "../../deployments/localhost/DataProvider.json";
import diamondJson from "../../deployments/localhost/Diamond.json";

const { dpDiamond } = await instantiateContracts();
const assetToAddress = await createAssetToAddress();

async function instantiateContracts() {
  const provider = new ethers.providers.Web3Provider(window.ethereum),
    signer = provider.getSigner(),
    dpDiamond = new ethers.Contract(diamondJson.address, dpJson.abi, signer);

  return { dpDiamond };
}

async function createAssetToAddress() {
  const assets = await getAllActivePoolAssetNames(),
    addresses = await getAllActivePools(),
    assetToAddress = {};

  assets.forEach((asset, i) => (assetToAddress[asset] = addresses[i]));

  return assetToAddress;
}

async function getAllActivePools() {
  return await dpDiamond.getAllActivePools();
}

async function getAllActivePoolAssetNames() {
  return await dpDiamond.getAllActivePoolAssetNames();
}

async function getActivePoolsDisplayData() {
  const poolsDisplayData = [];
  const activePools = await getAllActivePools();
  for (const pool of activePools) {
    const res = await dpDiamond.getPoolDisplayData(pool);
    poolsDisplayData.push(assignDisplayDataProperties({}, res));
  }

  return poolsDisplayData;
}

function assignDisplayDataProperties(displayData, res) {
  console.log(Object.getOwnPropertyNames(res));
  displayData.asset = res.asset;
  displayData.loanToValue = parseInt(res.loanToValue);
  displayData.liquidationThreshold = parseInt(res.liquidationThreshold);
  displayData.liquidationBonus = parseInt(res.liquidationBonus);
  displayData.providedLiquidity = parseInt(res.depositedLiquidity);
  displayData.borrowedLiquidity = parseInt(res.borrowedLiquidity);
  displayData.isBorrowingEnabled = res.isBorrowingEnabled;
  displayData.isUsableAsCollateral = res.isUsableAsCollateral;
  displayData.isActive = res.isActive;

  return displayData;
}

async function getPoolDisplayData(pool) {
  return await dpDiamond.getPoolDisplayData(pool);
}

async function getPoolDepositData(asset) {
  const res = await dpDiamond.getPoolDepositData(assetToAddress[asset]);
  const poolDepositData = {
    asset: res.asset,
    depositedLiquidity: ethers.utils.formatEther(res.depositedLiquidity),
    borrowedLiquidity: ethers.utils.formatEther(res.borrowedLiquidity),
    overallBorrowRate: parseInt(res.overallBorrowRate),
    currentLiquidityRate: parseInt(res.currentLiquidityRate),
    depositAPY: parseInt(res.depositAPY),
    isUsableAsCollateral: res.isUsableAsCollateral,
  };

  return poolDepositData;
}

export {
  getActivePoolsDisplayData,
  getAllActivePoolAssetNames,
  getPoolDepositData,
};
