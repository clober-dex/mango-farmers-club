// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITokenReceiver.sol";
import "../clober/CloberMarketSwapCallbackReceiver.sol";

interface ICloberExchanger is ITokenReceiver, CloberMarketSwapCallbackReceiver {
    function inputToken() external view returns (address);

    function outputToken() external view returns (address);

    function outputTokenReceiver() external view returns (ITokenReceiver);

    function market() external view returns (address);

    function currentOrderId() external view returns (uint256);

    function transferableAmount() external view returns (uint256);

    function hasNoOpenOrder() external view returns (bool);

    function limitOrder(uint16 priceIndex) external;

    function transferOutputToken() external;

    function setReceiver(ITokenReceiver receiver) external;

    function withdrawLostERC20(address token, address to) external;
}
