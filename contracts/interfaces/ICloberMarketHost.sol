// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITokenReceiver.sol";

interface ICloberMarketHost {
    event SetTokenReceiver(address indexed token, address indexed receiver);

    function tokenReceiver(address token) external view returns (address);

    function distributeTokens(address[] calldata tokenList) external;

    function setTokenReceiver(ITokenReceiver receiver) external;

    function withdrawLostERC20(address token, address to) external;
}
