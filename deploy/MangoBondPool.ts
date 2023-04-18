import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'

import { BOND_CONFIG, BURN_ADDRESS, TOKEN, getDeployedContract } from '../utils'
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
  const treasury = await getDeployedContract<MangoTreasury>('MangoTreasury')
  const bondConfig = BOND_CONFIG[network.config.chainId]
  await deploy('MangoBondPool', {
    from: deployer,
    args: [
      treasury.address,
      BURN_ADDRESS,
      TOKEN[network.config.chainId].MANGO,
      bondConfig.cancelFee,
      bondConfig.market,
      bondConfig.releaseRate,
      bondConfig.maxReleaseAmount,
      bondConfig.initialBondPrice,
    ],
    proxy: {
      proxyContract: 'OpenZeppelinTransparentProxy',
      execute: {
        init: {
          methodName: 'initialize',
          args: [
            bondConfig.minBonus,
            bondConfig.maxBonus,
            bondConfig.startsAt,
            bondConfig.sampleSize,
          ],
        },
      },
    },
    log: true,
  })
}

deployFunction.tags = ['MangoBondPool']
deployFunction.dependencies = ['MangoTreasury', 'MangoStakedToken']
export default deployFunction
