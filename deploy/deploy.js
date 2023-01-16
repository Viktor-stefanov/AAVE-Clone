const {
  increase,
} = require("@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time");
const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const [user1, user2] = await ethers.getSigners();

  const lp = await deploy("LendingPool", { from: deployer, log: true }),
    lpc = await deploy("LendingPoolCore", { from: deployer, log: true }),
    lpconf = await deploy("LendingPoolConfigurator", {
      from: deployer,
      log: true,
    }),
    pf = await deploy("PriceFeed", { from: deployer, log: true }),
    dp = await deploy("DataProvider", { from: deployer, log: true }),
    fp = await deploy("FeeProvider", { from: deployer, log: true }),
    ethAggregator = await deploy("EthMock", {
      from: deployer,
      log: true,
      args: [18, 1500],
    }),
    usdcAggregator = await deploy("UsdcAggregator", {
      from: deployer,
      log: true,
      args: [18, 1],
    }),
    usdcMock = await deploy("UsdcMock", {
      from: deployer,
      log: true,
      args: [user2.address],
    });

  // add ETH price oracle
  const p = new ethers.Contract(pf.address, pf.abi, await ethers.getSigner());
  await p.addAssetOracle(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    ethAggregator.address
  );
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
      "0x79a6dda6dc83994a466272f1c845e6156267cf78",
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

  let d = new ethers.Contract(diamond.address, lpconf.abi, user1);

  await d.initPool("0x79a6dda6dc83994a466272f1c845e6156267cf78", 18, 1);
  await d.initPool(usdcMock.address, 18, 0);

  let di = new ethers.Contract(diamond.address, lp.abi, user1);

  await di.deposit(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    user1.address,
    ethers.utils.parseEther("10"),
    { value: ethers.utils.parseEther("10") }
  );

  di = new ethers.Contract(diamond.address, lp.abi, user2);

  await di.deposit(
    usdcMock.address,
    user2.address,
    ethers.utils.parseEther("1500")
  );

  await di.borrow(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    ethers.utils.parseEther("0.5"),
    0
  );

  await di.test("0x79a6dda6dc83994a466272f1c845e6156267cf78", user2.address);

  await increase(60 * 60 * 24 * 365);

  await di.test("0x79a6dda6dc83994a466272f1c845e6156267cf78", user2.address);

  //await di.borrow(
  //  "0x79a6dda6dc83994a466272f1c845e6156267cf78",
  //  ethers.utils.parseEther("0.5"),
  //  0
  //);

  //await di.repay(
  //  "0x79a6dda6dc83994a466272f1c845e6156267cf78",
  //  ethers.utils.parseEther("3")
  //);

  //di.connect(user1);

  //await di.redeem(
  //  "0x79a6dda6dc83994a466272f1c845e6156267cf78",
  //  ethers.utils.parseEther("3")
  //);
};
