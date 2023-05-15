import { hardhat, polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'
import { BigNumber } from 'ethers'

export const GAS_BUF = {
  [hardhat.id]: 1,
  [polygonZkEvmTestnet.id]: 1.5,
  [polygonZkEvm.id]: 1,
}

export const PUBLIC_REGISTRATION_START_TIME = {
  [hardhat.id]: Math.floor(Date.now() / 1000) + 60 * 5,
  [polygonZkEvmTestnet.id]: Math.floor(Date.now() / 1000) + 60 * 5,
  [polygonZkEvm.id]: 1681740000,
}

export const TOKEN = {
  [hardhat.id]: {
    MANGO: '0x1c1f6B8d0e4D83347fCA9fF16738DF482500EeA5',
    USDC: '0x4d7E15fc589EbBF7EDae1B5236845b3A42D412B7',
  },
  [polygonZkEvmTestnet.id]: {
    MANGO: '0x1c1f6B8d0e4D83347fCA9fF16738DF482500EeA5',
    USDC: '0x4d7E15fc589EbBF7EDae1B5236845b3A42D412B7',
  },
  [polygonZkEvm.id]: {
    MANGO: '0x1fA03eDB1B8839a5319A7D2c1Ae6AAE492342bAD',
    USDC: '0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035',
  },
}

export const CLOBER_MARKET: {
  [network: string]: { [marketName: string]: string }
} = {
  [hardhat.id]: {
    'MANGO/USDC': '0x8E02612391843175B13883a284FD65A6C66FDD79',
  },
  [polygonZkEvmTestnet.id]: {
    'MANGO/USDC': '0x8E02612391843175B13883a284FD65A6C66FDD79',
  },
  [polygonZkEvm.id]: {
    'MANGO/USDC': '0x1FC38BA10E741F357b1c8B69DC08eA654c21Ae37',
  },
}

export const TREASURY_START_TIME = {
  [hardhat.id]: Math.floor(Date.now() / 1000),
  [polygonZkEvmTestnet.id]: Math.floor(Date.now() / 1000),
  [polygonZkEvm.id]:
    PUBLIC_REGISTRATION_START_TIME[polygonZkEvm.id] + 7 * 86400 + 10 * 60,
}

export const BURN_ADDRESS = '0x000000000000000000000000000000000000dEaD'

export type BondConfig = {
  cancelFee: number
  market: string
  releaseRate: BigNumber
  maxReleaseAmount: BigNumber
  initialBondPrice: number
  minBonus: number
  maxBonus: number
  startsAt: number
  sampleSize: number
}
export const BOND_CONFIG: { [network: string]: BondConfig } = {
  [hardhat.id]: {
    cancelFee: 200000,
    market: CLOBER_MARKET[hardhat.id]['MANGO/USDC'],
    maxReleaseAmount: BigNumber.from(5).mul(BigNumber.from(10).pow(27)),
    releaseRate: BigNumber.from(5)
      .mul(BigNumber.from(10).pow(27))
      .div(3600 * 24 * 500), // 5 * 10**27 / (60 * 60 * 24 * 500)
    initialBondPrice: 220,
    minBonus: 5,
    maxBonus: 15,
    startsAt: TREASURY_START_TIME[hardhat.id],
    sampleSize: 10,
  },
  [polygonZkEvmTestnet.id]: {
    cancelFee: 200000,
    market: CLOBER_MARKET[polygonZkEvmTestnet.id]['MANGO/USDC'],
    maxReleaseAmount: BigNumber.from(5).mul(BigNumber.from(10).pow(27)),
    releaseRate: BigNumber.from(5)
      .mul(BigNumber.from(10).pow(27))
      .div(3600 * 24 * 500), // 5 * 10**27 / (60 * 60 * 24 * 500)
    initialBondPrice: 220,
    minBonus: 5,
    maxBonus: 15,
    startsAt: TREASURY_START_TIME[polygonZkEvmTestnet.id],
    sampleSize: 10,
  },
  [polygonZkEvm.id]: {
    cancelFee: 200000,
    market: CLOBER_MARKET[polygonZkEvm.id]['MANGO/USDC'],
    maxReleaseAmount: BigNumber.from(4).mul(BigNumber.from(10).pow(27)),
    releaseRate: BigNumber.from(4)
      .mul(BigNumber.from(10).pow(27))
      .div(3600 * 24 * 500), // 4 * 10**27 / (60 * 60 * 24 * 500)
    initialBondPrice: 220,
    minBonus: 5,
    maxBonus: 15,
    startsAt: TREASURY_START_TIME[polygonZkEvm.id],
    sampleSize: 10,
  },
}
