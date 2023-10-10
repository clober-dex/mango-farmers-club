import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'
import { BigNumber } from 'ethers'

import {
  GAS_BUF,
  getDeployedContract,
  getEthBalance,
  liveLog,
  TOKEN,
  TREASURY_START_TIME,
  waitForTx,
} from '../utils'

const deployFunction: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments, ethers, getNamedAccounts, network } = hre
  if (
    network.config.chainId !== hardhat.id &&
    network.config.chainId !== polygonZkEvm.id &&
    network.config.chainId !== polygonZkEvmTestnet.id
  ) {
    return
  }

  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  liveLog(`Before Eth balance ${await getEthBalance(deployer)}`)
  const multiplier = BigNumber.from(
    Math.floor(GAS_BUF[network.config.chainId] * 100),
  )
  const gasPrice = (await hre.ethers.provider.getGasPrice())
    .mul(multiplier)
    .div(100)
  const stakedTokenDeployResult = await deploy('MangoStakedToken', {
    from: deployer,
    args: [TOKEN[network.config.chainId].MANGO],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
    },
    log: true,
    gasPrice,
  })

  const treasuryDeployResult = await deploy('MangoTreasury', {
    from: deployer,
    // not valid for initial deploy
    args: [
      stakedTokenDeployResult.address,
      TOKEN[network.config.chainId].USDC,
      (await getDeployedContract('MangoBondPool')).address,
    ],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [TREASURY_START_TIME[network.config.chainId]],
        },
      },
    },
    log: true,
    gasPrice,
  })
  const stakedToken = await ethers.getContractAt(
    'MangoStakedToken',
    stakedTokenDeployResult.address,
  )
  if ((await stakedToken.rewardTokensLength()).eq(0)) {
    const receipt = await waitForTx(
      stakedToken.initialize(
        [TOKEN[network.config.chainId].USDC],
        [treasuryDeployResult.address],
      ),
    )
    liveLog(`Initialize StakedToken on tx ${receipt.transactionHash}`)
  }
}

deployFunction.tags = ['MangoStakedToken', 'MangoTreasury']
deployFunction.dependencies = []
export default deployFunction
