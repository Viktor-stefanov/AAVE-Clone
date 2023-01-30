import { ethers } from "ethers";
import ethMockJson from "../../deployments/localhost/EthMock.json";
import usdcMockJson from "../../deployments/localhost/UsdcMock.json";
import lpJson from "../../deployments/localhost/LendingPool.json";
import dpJson from "../../deployments/localhost/DataProvider.json";
import diamondJson from "../../deployments/localhost/Diamond.json";

const { dpDiamond, lpDiamond, ethMock, usdcMock } =
  await instantiateContracts();
const assetToMock = { ETH: ethMock, USDC: usdcMock };
let assetToAddress = {};

document.addEventListener(
  "onCorrectNetwork",
  async () => (assetToAddress = await createAssetToAddress())
);

async function instantiateContracts() {
  const web3Provider = new ethers.providers.Web3Provider(window.ethereum),
    signer = web3Provider.getSigner(),
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
    const res = await dpDiamond.getPoolDisplayData(
      pool,
      await dpDiamond.signer.getAddress()
    );
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
  displayData.userBorrowedLiquidity = ethers.utils.formatEther(
    res.userBorrowedLiquidity
  );
  displayData.userRepayAmount = ethers.utils.formatEther(res.userRepayAmount);
  displayData.isBorrowingEnabled = res.isBorrowingEnabled;
  displayData.isUsableAsCollateral = res.isUsableAsCollateral;

  return displayData;
}

async function calculateExpectedBorrowInterestRate(asset, amount) {
  return ethers.utils.formatEther(
    await dpDiamond.calculateExpectedVariableBorrowRate(
      assetToAddress[asset],
      ethers.utils.parseEther(amount.toString())
    )
  );
}

async function getUserCollateralBalance(address) {
  return ethers.utils.formatEther(
    await dpDiamond.getUserCollateralAmount(
      address,
      await dpDiamond.signer.getAddress()
    )
  );
}

async function getPoolDepositData(asset) {
  const res = await dpDiamond.getPoolLendData(
    assetToAddress[asset],
    await dpDiamond.signer.getAddress()
  );
  const poolDepositData = {
    asset: res.asset,
    depositAPY: parseFloat(
      ethers.utils.formatEther(res.depositAPY) * 100
    ).toPrecision(5),
    depositedLiquidity: ethers.utils.formatEther(res.depositedLiquidity),
    userDepositedLiquidity: ethers.utils.formatEther(
      res.userDepositedLiquidity
    ),
    userMaxRedeemAmount: ethers.utils.formatEther(res.userMaxRedeemAmount),
    borrowedLiquidity: ethers.utils.formatEther(res.borrowedLiquidity),
    overallBorrowRate: parseInt(res.overallBorrowRate),
    currentLiquidityRate: parseInt(res.currentLiquidityRate),
    loanToValue: parseInt(res.loanToValue),
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

async function repay(asset, amount, repayingWholeLoan) {
  const amountInWei = ethers.utils.parseEther(amount),
    paybackAmount =
      asset === "ETH"
        ? repayingWholeLoan
          ? amountInWei.add(10 ** 13)
          : amountInWei
        : 0;
  await lpDiamond.repay(assetToAddress[asset], paybackAmount, {
    value: paybackAmount,
  });
}

async function redeem(asset, amount) {
  const amountInWei = ethers.utils.parseEther(amount.toString());
  await (await lpDiamond.redeem(assetToAddress[asset], amountInWei)).wait();
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

async function getUserPoolData(address) {
  const userData = await dpDiamond.getUserPoolData(
    address,
    await dpDiamond.signer.getAddress()
  );
  return {
    compoundedBorrowBalance: userData.currentBorrowBalance,
  };
}

async function skipOneYear() {
  const provider = new ethers.providers.JsonRpcProvider(
    "http://127.0.0.1:8545"
  );
  await provider.send("evm_increaseTime", [60 * 60 * 24 * 365]);
  console.log("skipped time");
}
async function getMaxAmountToRepayOnLiquidation(pool, userToLiquidate) {
  return ethers.utils.formatEther(
    await dpDiamond.getMaxAmountToRepayOnLiquidation(pool, userToLiquidate)
  );
}

async function getRepayAndCollateralOnLiquidation(
  pool,
  collateral,
  userCollateralBalance
) {
  return (
    await dpDiamond.calculateAvailableCollateralToLiquidate(
      pool,
      collateral,
      ethers.utils.parseEther("1000000"),
      ethers.utils.parseEther(userCollateralBalance.toString())
    )
  ).map((val) => ethers.utils.formatEther(val.toString()) / 2);
}

async function liquidationCall(pool, collateral, userToLiquidate, amount) {
  await lpDiamond.liquidationCall(
    pool,
    collateral,
    userToLiquidate,
    ethers.utils.parseEther(amount.toString()),
    {
      value:
        pool === ethMock.address
          ? ethers.utils.parseEther(amount.toString())
          : 0,
    }
  );
}

export {
  getRepayAndCollateralOnLiquidation,
  calculateExpectedBorrowInterestRate,
  getMaxAmountToRepayOnLiquidation,
  getActivePoolsDisplayData,
  getAllActivePoolAssetNames,
  getUserCollateralBalance,
  getPoolDepositData,
  getUserGlobalData,
  getUserPoolData,
  liquidationCall,
  deposit,
  borrow,
  repay,
  redeem,
};
