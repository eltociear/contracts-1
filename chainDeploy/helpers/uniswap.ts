import { SALT } from "../../deploy/deploy";
import { UniswapTwapPriceOracleV2Factory } from "../../typechain/UniswapTwapPriceOracleV2Factory";
import { constants } from "ethers";
import { UniswapDeployFnParams } from "./types";

export const deployUniswapOracle = async ({
  run,
  ethers,
  getNamedAccounts,
  deployments,
  deployConfig,
}: UniswapDeployFnParams): Promise<void> => {
  const { deployer } = await getNamedAccounts();
  //// Uniswap Oracle
  let dep = await deployments.deterministic("UniswapTwapPriceOracleV2Root", {
    from: deployer,
    salt: ethers.utils.keccak256(ethers.utils.toUtf8Bytes(SALT)),
    args: [deployConfig.wtoken],
    log: true,
  });
  const utpor = await dep.deploy();
  if (utpor.transactionHash) await ethers.provider.waitForTransaction(utpor.transactionHash);
  console.log("UniswapTwapPriceOracleV2Root: ", utpor.address);

  dep = await deployments.deterministic("UniswapTwapPriceOracleV2", {
    from: deployer,
    salt: ethers.utils.keccak256(ethers.utils.toUtf8Bytes(SALT)),
    args: [],
    log: true,
  });
  const utpo = await dep.deploy();
  if (utpo.transactionHash) await ethers.provider.waitForTransaction(utpo.transactionHash);
  console.log("UniswapTwapPriceOracleV2: ", utpo.address);

  dep = await deployments.deterministic("UniswapTwapPriceOracleV2Factory", {
    from: deployer,
    salt: ethers.utils.keccak256(ethers.utils.toUtf8Bytes(SALT)),
    args: [utpor.address, utpo.address, deployConfig.wtoken],
    log: true,
  });
  const utpof = await dep.deploy();
  if (utpof.transactionHash) await ethers.provider.waitForTransaction(utpof.transactionHash);
  console.log("UniswapTwapPriceOracleV2Factory: ", utpof.address);

  const uniTwapOracleFactory = (await ethers.getContract(
    "UniswapTwapPriceOracleV2Factory",
    deployer
  )) as UniswapTwapPriceOracleV2Factory;

  const existingOracle = await uniTwapOracleFactory.callStatic.oracles(
    deployConfig.uniswap.uniswapV2FactoryAddress,
    deployConfig.wtoken
  );
  if (existingOracle == constants.AddressZero) {
    // deploy oracle with wtoken as base token
    let tx = await uniTwapOracleFactory.deploy(deployConfig.uniswap.uniswapV2FactoryAddress, deployConfig.wtoken);
    await tx.wait();
  } else {
    console.log("UniswapTwapPriceOracleV2 already deployed at: ", existingOracle);
  }

  const nativeOracle = await uniTwapOracleFactory.callStatic.oracles(
    deployConfig.uniswap.uniswapV2FactoryAddress,
    deployConfig.wtoken
  );

  const mpo = await ethers.getContract("MasterPriceOracle", deployer);
  const underlyings = deployConfig.uniswap.uniswapOracleInitialDeployTokens;
  const oracles = Array(deployConfig.uniswap.uniswapOracleInitialDeployTokens.length).fill(nativeOracle);

  if (underlyings.length > 0) {
    let anyNotAddedYet = underlyings.some(
      async (underlying) => (await mpo.callStatic.oracles(underlying)) == constants.AddressZero
    );
    if (anyNotAddedYet) {
      let tx = await mpo.add(underlyings, oracles);
      await tx.wait();
      console.log(`Master Price Oracle updated for tokens ${underlyings.join(", ")}`);
    }
  }
};
