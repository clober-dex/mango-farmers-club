import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'
import { BigNumber } from 'ethers'

import { GAS_BUF, getDeployedContract, getEthBalance, liveLog } from '../utils'
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
  const multiplier = BigNumber.from(
    Math.floor(GAS_BUF[network.config.chainId] * 100),
  )
  const gasPrice = (await hre.ethers.provider.getGasPrice())
    .mul(multiplier)
    .div(100)
  const treasury = await getDeployedContract<MangoTreasury>('MangoTreasury')
  const exchanger = await getDeployedContract<MangoCloberExchanger>(
    'CloberMangoUSDCExchanger',
  )
  await deploy('MangoHost', {
    from: deployer,
    args: ['0x24aC0938C010Fb520F1068e96d78E0458855111D'],
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
    gasPrice,
  })
  liveLog(`After Eth balance ${await getEthBalance(deployer)}`)
}

deployFunction.tags = ['MangoHost']
deployFunction.dependencies = ['MangoTreasury', 'MangoCloberExchanger']
export default deployFunction
