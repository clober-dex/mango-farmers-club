import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'

import { PUBLIC_REGISTRATION_START_TIME, TOKEN } from '../utils/constant'

const deployFunction: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment,
) {
  const { deployments, getNamedAccounts, network } = hre
  if (
    network.config.chainId !== polygonZkEvm.id &&
    network.config.chainId !== polygonZkEvmTestnet.id
  ) {
    return
  }

  const { deploy } = deployments

  const { deployer } = await getNamedAccounts()
  await deploy('MangoPublicRegistration', {
    from: deployer,
    args: [
      PUBLIC_REGISTRATION_START_TIME[network.config.chainId],
      TOKEN[network.config.chainId].MANGO,
      TOKEN[network.config.chainId].USDC,
    ],
    log: true,
  })
}

deployFunction.tags = ['MangoPublicRegistration']
deployFunction.dependencies = []
export default deployFunction
