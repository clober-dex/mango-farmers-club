// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ITokenReceiver.sol";

interface ITreasury is ITokenReceiver {
    event Distribute(uint256 amount, uint256 elapsed);

    function stakedToken() external view returns (address);

    function rewardToken() external view returns (address);

    function lastDistributedAt() external view returns (uint256);

    // precision 18
    // tokens per second
    function rewardRate() external view returns (uint256);

    function getDistributableAmount() external view returns (uint256);

    function distribute() external;

    function withdrawLostERC20(address token, address to) external;
}
