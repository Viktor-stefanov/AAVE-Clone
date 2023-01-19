const {
  increase,
} = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time");
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const lp = await deploy("LendingPool", { from: deployer, log: true }),
    lpc = await deploy("LendingPoolCore", { from: deployer, log: true }),
    lpconf = await deploy("LendingPoolConfigurator", {
      from: deployer,
      log: true,
    }),
    pf = await deploy("PriceFeed", { from: deployer, log: true }),
    dp = await deploy("DataProvider", { from: deployer, log: true }),
    fp = await deploy("FeeProvider", { from: deployer, log: true }),
    ethAggregator = await deploy("EthAggregator", {
      from: deployer,
      log: true,
      args: [18, 1500],
    }),
    usdcAggregator = await deploy("UsdcAggregator", {
      from: deployer,
      log: true,
      args: [18, 1],
    }),
    ethMock = await deploy("EthMock", {
      from: deployer,
      log: true,
    }),
    usdcMock = await deploy("UsdcMock", {
      from: deployer,
      log: true,
      args: [(await ethers.getSigners())[1].address],
    });

  const p = new ethers.Contract(pf.address, pf.abi, await ethers.getSigner());
  await p.addAssetOracle(ethMock.address, ethAggregator.address);
  await p.addAssetOracle(usdcMock.address, usdcAggregator.address);

  const iLpc = new ethers.utils.Interface(lpc.abi),
    lpcFunctions = lpc.abi.filter((a) => a.type === "function"),
    lpcSelectors = lpcFunctions.map((func) => iLpc.getSighash(func.name));

  const iLp = new ethers.utils.Interface(lp.abi),
    lpFunctions = lp.abi.filter((a) => a.type === "function"),
    lpSelectors = lpFunctions.map((func) => iLp.getSighash(func.name));

  const iFp = new ethers.utils.Interface(fp.abi),
    fpFunctions = fp.abi.filter((a) => a.type === "function"),
    fpSelectors = fpFunctions.map((func) => iFp.getSighash(func.name));

  const iDp = new ethers.utils.Interface(dp.abi),
    dpFunctions = dp.abi.filter((a) => a.type === "function"),
    dpSelectors = dpFunctions.map((func) => iDp.getSighash(func.name));

  const iLpconf = new ethers.utils.Interface(lpconf.abi),
    initCallData = iLpconf.encodeFunctionData("init", [
      ethMock.address,
      lpc.address,
      pf.address,
      dp.address,
    ]);

  const diamond = await deploy("Diamond", {
    from: deployer,
    log: true,
    args: [
      [
        [fp.address, 0, fpSelectors],
        [dp.address, 0, dpSelectors],
        [lpc.address, 0, lpcSelectors],
        [
          lpconf.address,
          0,
          [iLpconf.getSighash("initPool"), iLpconf.getSighash("init")],
        ],
        [lp.address, 0, lpSelectors],
      ],
      [deployer, lpconf.address, initCallData],
    ],
  });

  const d = new ethers.Contract(
    diamond.address,
    lpconf.abi,
    await ethers.getSigner()
  );

  await d.initPool(ethMock.address, "ETH", 18, 1);
  await d.initPool(usdcMock.address, "USDC", 18, 0);

  const di = new ethers.Contract(
    diamond.address,
    lp.abi,
    (await ethers.getSigners())[0]
  );

  await di.deposit(ethMock.address, ethers.utils.parseEther("5"), {
    value: ethers.utils.parseEther("5"),
  });

  const dia = new ethers.Contract(
    diamond.address,
    lp.abi,
    (await ethers.getSigners())[1]
  );

  const usdc = new ethers.Contract(
    usdcMock.address,
    usdcMock.abi,
    (await ethers.getSigners())[1]
  );
  await usdc.increaseAllowance(dia.address, ethers.utils.parseEther("6000"));

  await dia.deposit(usdcMock.address, ethers.utils.parseEther("6000"));

  await dia.borrow(ethMock.address, ethers.utils.parseEther("2"), 0);

  //await di.test(ethMock.address, deployer);

  //await increase(60 * 60 * 24 * 365);

  //const repayAmount = await dia.calculateUserAmountToRepay(
  //  ethMock.address,
  //  (
  //    await ethers.getSigners()
  //  )[1].address
  //);

  //console.log(repayAmount);

  //await dia.repay(ethMock.address, repayAmount, { value: repayAmount });

  //console.log(
  //  await di.getUserMaxRedeemAmount(
  //    ethMock.address,
  //    (
  //      await ethers.getSigners()
  //    )[0].address
  //  )
  //);
};
