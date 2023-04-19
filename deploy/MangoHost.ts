import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'

import { getDeployedContract } from '../utils'
import { MangoCloberExchanger, MangoTreasury } from '../typechain'

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
  const treasury = await getDeployedContract<MangoTreasury>('MangoTreasury')
  const exchanger = await getDeployedContract<MangoCloberExchanger>(
    'CloberMangoUSDCExchanger',
  )
  await deploy('MangoHost', {
    from: deployer,
    args: [],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [[treasury.address, exchanger.address]],
        },
      },
    },
    log: true,
  })
}

deployFunction.tags = ['MangoHost']
deployFunction.dependencies = ['MangoTreasury', 'MangoCloberExchanger']
export default deployFunction
