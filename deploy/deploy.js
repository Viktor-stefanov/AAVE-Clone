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
    ethAggregator = await deploy("EthMock", {
      from: deployer,
      log: true,
      args: [18, 1500],
    });

  // add ETH price oracle
  const p = new ethers.Contract(pf.address, pf.abi, await ethers.getSigner());
  await p.addAssetOracle(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    ethAggregator.address
  );

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

  let d = new ethers.Contract(
    diamond.address,
    lpconf.abi,
    await ethers.getSigner()
  );

  await d.initPool("0x79a6dda6dc83994a466272f1c845e6156267cf78", 18, 1);

  let di = new ethers.Contract(
    diamond.address,
    lp.abi,
    await ethers.getSigner()
  );

  await di.deposit(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    deployer,
    ethers.utils.parseEther("10"),
    { value: ethers.utils.parseEther("10") }
  );

  await di.borrow(
    "0x79a6dda6dc83994a466272f1c845e6156267cf78",
    ethers.utils.parseEther("3"),
    0
  );
};
