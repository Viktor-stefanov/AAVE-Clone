const {
  increase,
} = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time");
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer, deployer2 } = await getNamedAccounts();

  const [user1, user2, user3] = await ethers.getSigners();

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
      from: deployer2,
      log: true,
      args: [user2.address],
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

  const usdcContract = new ethers.Contract(
    usdcMock.address,
    usdcMock.abi,
    user2
  );
  await usdcContract.approve(diamond.address, ethers.utils.parseEther("1500"));

  let d = new ethers.Contract(diamond.address, lpconf.abi, user1);
  await d.initPool(ethMock.address, 18, 1);
  await d.initPool(usdcMock.address, 18, 0);

  let di = new ethers.Contract(diamond.address, lp.abi, user1);
  await di.deposit(
    ethMock.address,
    user3.address,
    ethers.utils.parseEther("5"),
    { value: ethers.utils.parseEther("5") }
  );

  di = new ethers.Contract(diamond.address, lp.abi, user3);
  await di.deposit(
    ethMock.address,
    user1.address,
    ethers.utils.parseEther("5"),
    { value: ethers.utils.parseEther("5") }
  );

  di = new ethers.Contract(diamond.address, lp.abi, user2);
  await di.deposit(
    usdcMock.address,
    user2.address,
    ethers.utils.parseEther("1500")
  );

  await di.borrow(ethMock.address, ethers.utils.parseEther("0.5"), 0);

  await increase(60 * 60 * 24 * 365); // one year

  const repayAmount = ethers.utils.formatEther(
    await di.calculateUserAmountToRepay(ethMock.address, user2.address)
  );

  await di.repay(
    ethMock.address,
    ethers.utils.parseEther(repayAmount.toString()),
    { value: ethers.utils.parseEther(repayAmount.toString()) }
  );

  let redeemAmount = await di.getUserMaxRedeemAmount(
    ethMock.address,
    user1.address
  );
  await di.redeem(ethMock.address, user1.address, redeemAmount);

  await increase(60 * 60 * 24 * 365); // one year

  redeemAmount = await di.getUserMaxRedeemAmount(
    ethMock.address,
    user3.address
  );
  await di.redeem(ethMock.address, user3.address, redeemAmount);

  //await di.test("0x79a6dda6dc83994a466272f1c845e6156267cf78", user2.address);

  //console.log(
  //  ethers.utils.formatEther(
  //    await di.calculateUserAmountToRepay(
  //      "0x79a6dda6dc83994a466272f1c845e6156267cf78",
  //      user2.address
  //    )
  //  )
  //);

  //di.connect(user1);
};
