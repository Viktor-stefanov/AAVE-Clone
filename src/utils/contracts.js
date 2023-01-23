import { ethers } from "ethers";
import ethMockJson from "../../deployments/localhost/EthMock.json";
import usdcMockJson from "../../deployments/localhost/UsdcMock.json";
import lpJson from "../../deployments/localhost/LendingPool.json";
import dpJson from "../../deployments/localhost/DataProvider.json";
import diamondJson from "../../deployments/localhost/Diamond.json";

const { dpDiamond, lpDiamond, ethMock, usdcMock } =
  await instantiateContracts();
//const assetToAddress = await createAssetToAddress();
//const assetToMock = { ETH: ethMock, USDC: usdcMock };

async function instantiateContracts() {
  const provider = new ethers.providers.Web3Provider(window.ethereum),
    signer = provider.getSigner(),
    ethMock = new ethers.Contract(ethMockJson.address, ethMockJson.abi, signer),
    usdcMock = new ethers.Contract(
      usdcMockJson.address,
      usdcMockJson.abi,
      signer
    ),
    dpDiamond = new ethers.Contract(diamondJson.address, dpJson.abi, signer),
    lpDiamond = new ethers.Contract(diamondJson.address, lpJson.abi, signer);

  return { dpDiamond, lpDiamond, ethMock, usdcMock };
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
  displayData.asset = res.asset;
  displayData.loanToValue = parseInt(res.loanToValue);
  displayData.liquidationThreshold = parseInt(res.liquidationThreshold);
  displayData.liquidationBonus = parseInt(res.liquidationBonus);
  displayData.providedLiquidity = ethers.utils.formatEther(
    res.depositedLiquidity
  );
  displayData.borrowedLiquidity = ethers.utils.formatEther(
    res.borrowedLiquidity
  );
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
    depositAPY: parseFloat(
      ethers.utils.formatEther(res.depositAPY) * 100
    ).toPrecision(5),
    depositedLiquidity: ethers.utils.formatEther(res.depositedLiquidity),
    borrowedLiquidity: ethers.utils.formatEther(res.borrowedLiquidity),
    overallBorrowRate: parseInt(res.overallBorrowRate),
    currentLiquidityRate: parseInt(res.currentLiquidityRate),
    isUsableAsCollateral: res.isUsableAsCollateral,
  };

  return poolDepositData;
}

async function deposit(asset, amount, useAsCollateral) {
  const amountInWei = ethers.utils.parseEther(amount.toString());
  if (asset !== "ETH")
    await assetToMock[asset].approve(lpDiamond.address, amountInWei);

  await lpDiamond.deposit(assetToAddress[asset], amountInWei, useAsCollateral, {
    value: asset === "ETH" ? amountInWei : 0,
  });
}

async function borrow(asset, amount, rateMode) {
  await lpDiamond.borrow(
    assetToAddress[asset],
    ethers.utils.parseEther(amount.toString()),
    rateMode
  );
}

async function repay(asset, amount) {
  const amountInWei = ethers.utils.parseEther(amount.toString());
  await lpDiamond.repay(assetToAddress[asset], amountInWei, {
    value: asset === "ETH" ? amountInWei : 0,
  });
}

async function redeem(asset, amount) {
  await lpDiamond.redeem(
    assetToAddress[asset],
    ethers.utils.parseEther(amount)
  );
}

async function getUserGlobalData() {
  const res = await dpDiamond.getUserGlobalData(
      await lpDiamond.signer.getAddress()
    ),
    ret = {
      totalLiquidityProvided: parseFloat(res.totalLiquidityBalanceETH),
      totalCollateralBalance: parseFloat(res.totalCollateralBalanceETH),
      totalBorrowBalance: parseFloat(res.totalBorrowBalanceETH),
      totalFees: parseFloat(res.totalFeesETH),
      healthFactor: parseFloat(
        ethers.utils.formatEther(res.healthFactor)
      ).toPrecision(4),
      healthFactorBelowThreshold: res.healthFactorBelowThreshold,
    };

  return ret;
}

export {
  getActivePoolsDisplayData,
  getAllActivePoolAssetNames,
  getPoolDepositData,
  getUserGlobalData,
  deposit,
  borrow,
  repay,
  redeem,
};
