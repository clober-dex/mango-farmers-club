// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStakedToken {
    using SafeERC20 for IERC20;

    uint256 public supplyCount;
    uint256 public receiveAmount = type(uint256).max;

    function setReceiveAmount(uint256 amount) external {
        receiveAmount = amount;
    }

    function supplyReward(address token, uint256 amount) external returns (uint256) {
        if (receiveAmount < amount) {
            amount = receiveAmount;
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        supplyCount++;
        return amount;
    }
}
