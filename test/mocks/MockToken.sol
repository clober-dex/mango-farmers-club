// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor(uint256 totalSupply_) ERC20("Clober", "CLOB") {
        _mint(msg.sender, totalSupply_);
    }
}
