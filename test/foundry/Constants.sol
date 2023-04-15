// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Constants {
    string public constant TESTNET_RPC_URL = "https://rpc.public.zkevm-test.net";
    address public constant USER_A_ADDRESS = address(1);
    address public constant USER_B_ADDRESS = address(2);
    address public constant USER_C_ADDRESS = address(3);
    address public constant ORDER_CANCELER_ADDRESS = 0x03A2D3e0e4b073CDE7E227098B4257844910F094;
    address public constant MARKET_DEPLOYER_ADDRESS = 0x6baa80Fff765eB9994b65AfFA121517910316074;
    address public constant PRICEBOOK_DEPLOYER_ADDRESS = 0x30A075a4244a5A02e64a95eD3289234926baf02f;
    address public constant MARKET_FACTORY_ADDRESS = 0x7CE81Be8B48311D2E9e89fE4731B58D2CC8Aa1E4;
    address public constant MARKET_ROUTER_ADDRESS = 0x0ccc1fd632a5beE5bD9eda3aad490119eE50648F;

    address public constant MANGO_ADDRESS = 0x1c1f6B8d0e4D83347fCA9fF16738DF482500EeA5;
    address public constant USDC_ADDRESS = 0x4d7E15fc589EbBF7EDae1B5236845b3A42D412B7;
    address public constant MARKET_HOST_ADDRESS = 0x5F79EE8f8fA862E98201120d83c4eC39D9468D49;
    address public constant ADMIN_ADDRESS = 0x5F79EE8f8fA862E98201120d83c4eC39D9468D49;
    address public constant MANGO_USDC_MARKET_ADDRESS = 0x8E02612391843175B13883a284FD65A6C66FDD79;
    address public constant MANGO_USDC_WITH_MAKER_FEE_MARKET_ADDRESS = 0xF62302981718c8B6d28cF10a9A175FC227Fb27E8;

    uint256 public constant MANGO_TOTAL_SUPPLY = 10_000_000_000 * 10**18;
    uint256 public constant REWARD_RATE_RECIPROCAL = 1000 * 1 days;
}
