import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'
import { BigNumber } from 'ethers'

import { CLOBER_MARKET, GAS_BUF, getDeployedContract, TOKEN } from '../utils'
import { MangoTreasury } from '../typechain'

const deployFunction: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments, getNamedAccounts, network } = hre
  if (
    network.config.chainId !== hardhat.id &&
    network.config.chainId !== polygonZkEvm.id &&
    network.config.chainId !== polygonZkEvmTestnet.id
  ) {
    return
  }

  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  const multiplier = BigNumber.from(
    Math.floor(GAS_BUF[network.config.chainId] * 100),
  )
  const gasPrice = (await hre.ethers.provider.getGasPrice())
    .mul(multiplier)
    .div(100)
  const treasury = await getDeployedContract<MangoTreasury>('MangoTreasury')
  await deploy('CloberMangoUSDCExchanger', {
    from: deployer,
    contract: 'MangoCloberExchanger',
    args: [
      TOKEN[network.config.chainId].MANGO,
      TOKEN[network.config.chainId].USDC,
      CLOBER_MARKET[network.config.chainId]['MANGO/USDC'],
    ],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [treasury.address],
        },
      },
    },
    log: true,
    gasPrice,
  })
}

deployFunction.tags = ['MangoCloberExchanger']
deployFunction.dependencies = ['MangoTreasury']
export default deployFunction
