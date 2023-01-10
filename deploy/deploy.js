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
    pf = await deploy("PriceFeed", { from: deployer, log: true });

  const iLpc = new ethers.utils.Interface(lpc.abi),
    lpcFunctions = lpc.abi.filter((a) => a.type === "function"),
    lpcSelectors = lpcFunctions.map((func) => iLpc.getSighash(func.name));

  const iLp = new ethers.utils.Interface(lp.abi),
    lpFunctions = lp.abi.filter((a) => a.type === "function"),
    lpSelectors = lpFunctions.map((func) => iLp.getSighash(func.name));

  const iLpconf = new ethers.utils.Interface(lpconf.abi),
    initCallData = iLpconf.encodeFunctionData("init", [
      lp.address,
      lpc.address,
      pf.address,
    ]);

  const diamond = await deploy("Diamond", {
    from: deployer,
    log: true,
    args: [
      [
        [lpc.address, 0, lpcSelectors],
        [lpconf.address, 0, [iLpconf.getSighash("initPool")]],
      ],
      [deployer, lpconf.address, initCallData],
    ],
  });

  const lpConfABI = lpconf.abi;
  const d = new ethers.Contract(
    diamond.address,
    lpConfABI,
    await ethers.getSigner()
  );
  console.log(await d.initPool(lp.address, 1));

  //const diamondCut = await ethers.getContractAt("IDiamondCut", diamond.address);
  //console.log(
  //  await diamondCut.diamondCut(
  //    [[lpc.address, 0, lpcSelectors]],
  //    lpconf.address,
  //    initCallData
  //  )
  //);
};
