// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/interfaces/ITokenReceiver.sol";

contract MockTokenReceiver is ITokenReceiver {
    address public immutable override receivingToken;
    uint256 public callCount;

    constructor(address receivingToken_) {
        receivingToken = receivingToken_;
    }

    function receiveToken(uint256 amount) external {
        callCount++;
        IERC20(receivingToken).transferFrom(msg.sender, address(this), amount);
    }
}
