import { polygonZkEvm, polygonZkEvmTestnet } from '@wagmi/chains'

export const PUBLIC_REGISTRATION_START_TIME = {
  [polygonZkEvmTestnet.id]: Math.floor(Date.now() / 1000) + 60 * 5,
  [polygonZkEvm.id]: 1681740000,
}

export const TOKEN = {
  [polygonZkEvmTestnet.id]: {
    MANGO: '0x1c1f6B8d0e4D83347fCA9fF16738DF482500EeA5',
    USDC: '0x4d7E15fc589EbBF7EDae1B5236845b3A42D412B7',
  },
  [polygonZkEvm.id]: {
    MANGO: '0x1fA03eDB1B8839a5319A7D2c1Ae6AAE492342bAD',
    USDC: '0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035',
  },
}
